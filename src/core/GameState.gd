class_name GameState
extends RefCounted

enum Stage { WAITING, PRE_FLOP, FLOP, TURN, RIVER, SHOWDOWN }

enum Action { FOLD, CHECK, CALL, RAISE, ALL_IN }

signal state_changed(snapshot: Dictionary)
signal action_required(player_id: int, valid_actions: Array)
signal round_ended(winner_id: int, pot: int, hand_name: String)
signal game_ended(winner_id: int)

const HOST_ID := 1

var players: Array[Player] = []
var deck: Deck
var community_cards: Array[Card] = []
var stage: Stage = Stage.WAITING
var pot: int = 0
var current_bet: int = 0   # максимальная ставка в текущем раунде
var active_player_idx: int = 0
var dealer_idx: int = 0    # кто дилер (меняется каждый раунд)

var small_blind: int = 10
var big_blind: int = 20
var starting_chips: int = 1000

# --- Настройка ---

func setup(player_data: Array, settings: Dictionary) -> void:
	small_blind    = settings.get("small_blind", 10)
	big_blind      = settings.get("big_blind", 20)
	starting_chips = settings.get("starting_chips", 1000)
	players.clear()
	for pd in player_data:
		players.append(Player.new(pd["id"], pd["name"], starting_chips))

# --- Управление раундом ---

func start_round() -> void:
	deck = Deck.new()
	deck.shuffle()
	community_cards.clear()
	pot = 0
	current_bet = 0
	for p in players:
		p.reset_for_round()
	_deal_hole_cards()
	stage = Stage.PRE_FLOP
	_post_blinds()
	_next_action()
	emit_signal("state_changed", snapshot())

func process_action(player_id: int, action: Action, amount: int = 0) -> void:
	var p := _player_by_id(player_id)
	if p == null or p.id != current_player().id:
		return

	match action:
		Action.FOLD:
			p.is_folded = true
		Action.CHECK:
			pass
		Action.CALL:
			var diff := current_bet - p.current_bet
			pot += p.place_bet(diff)
		Action.RAISE:
			var diff := current_bet - p.current_bet
			pot += p.place_bet(diff + amount)
			current_bet = p.current_bet
		Action.ALL_IN:
			pot += p.place_bet(p.chips)
			if p.current_bet > current_bet:
				current_bet = p.current_bet

	if _only_one_left():
		_end_round_early()
		return

	if _betting_round_done():
		_advance_stage()
	else:
		_next_action()

	emit_signal("state_changed", snapshot())

# --- Снимок состояния (для сети) ---

func snapshot() -> Dictionary:
	var p_list := []
	for p in players:
		p_list.append(p.to_dict())
	var cc := []
	for c in community_cards:
		cc.append({ "rank": c.rank, "suit": c.suit })
	return {
		"stage":           stage,
		"pot":             pot,
		"current_bet":     current_bet,
		"active_player":   current_player().id if players.size() > 0 else -1,
		"community_cards": cc,
		"players":         p_list,
	}

# --- Приватные ---

func _deal_hole_cards() -> void:
	for _i in range(2):
		for p in players:
			p.hole_cards.append(deck.deal())

func _post_blinds() -> void:
	var sb_idx := (dealer_idx + 1) % players.size()
	var bb_idx := (dealer_idx + 2) % players.size()
	pot += players[sb_idx].place_bet(small_blind)
	pot += players[bb_idx].place_bet(big_blind)
	current_bet = big_blind
	active_player_idx = (bb_idx + 1) % players.size()

func _next_action() -> void:
	while not players[active_player_idx].can_act():
		active_player_idx = (active_player_idx + 1) % players.size()
	var p := players[active_player_idx]
	var valid := _valid_actions(p)
	emit_signal("action_required", p.id, valid)

func _valid_actions(p: Player) -> Array:
	var actions := [Action.FOLD]
	if p.current_bet == current_bet:
		actions.append(Action.CHECK)
	else:
		actions.append(Action.CALL)
	if p.chips > (current_bet - p.current_bet):
		actions.append(Action.RAISE)
	actions.append(Action.ALL_IN)
	return actions

func _betting_round_done() -> bool:
	var active := players.filter(func(p): return p.can_act())
	for p in active:
		if p.current_bet != current_bet:
			return false
	return true

func _only_one_left() -> bool:
	return players.filter(func(p): return not p.is_folded).size() == 1

func _advance_stage() -> void:
	for p in players:
		p.current_bet = 0
	current_bet = 0
	active_player_idx = (dealer_idx + 1) % players.size()

	match stage:
		Stage.PRE_FLOP:
			community_cards.append(deck.deal())
			community_cards.append(deck.deal())
			community_cards.append(deck.deal())
			stage = Stage.FLOP
			_next_action()
		Stage.FLOP:
			community_cards.append(deck.deal())
			stage = Stage.TURN
			_next_action()
		Stage.TURN:
			community_cards.append(deck.deal())
			stage = Stage.RIVER
			_next_action()
		Stage.RIVER:
			stage = Stage.SHOWDOWN
			_showdown()

func _showdown() -> void:
	var best_player: Player
	var best_result: Dictionary
	for p in players:
		if p.is_folded:
			continue
		var all_cards: Array = p.hole_cards.duplicate()
		all_cards.append_array(community_cards)
		var result := HandEvaluator.evaluate(all_cards)
		if best_result.is_empty() or HandEvaluator.compare(result, best_result) > 0:
			best_result = result
			best_player = p
	best_player.chips += pot
	var hand := HandEvaluator.hand_name(best_result["rank"])
	emit_signal("round_ended", best_player.id, pot, hand)
	pot = 0
	dealer_idx = (dealer_idx + 1) % players.size()
	_check_game_over()

func _end_round_early() -> void:
	var winner: Player
	for p in players:
		if not p.is_folded:
			winner = p
			break
	winner.chips += pot
	pot = 0
	emit_signal("round_ended", winner.id, pot, "")
	dealer_idx = (dealer_idx + 1) % players.size()
	_check_game_over()

func _check_game_over() -> void:
	var alive := players.filter(func(p): return p.chips > 0)
	if alive.size() == 1:
		emit_signal("game_ended", alive[0].id)

func current_player() -> Player:
	return players[active_player_idx]

func _player_by_id(pid: int) -> Player:
	for p in players:
		if p.id == pid:
			return p
	return null
