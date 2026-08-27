extends Control

# --- Узлы ---
@onready var stage_label: Label          = $Layout/TopArea/StageLabel
@onready var pot_label: Label            = $Layout/TopArea/PotLabel

@onready var opponent_name: Label        = $Layout/OpponentArea/NameLabel
@onready var opponent_chips: Label       = $Layout/OpponentArea/ChipsLabel
@onready var opponent_bet: Label         = $Layout/OpponentArea/BetLabel
@onready var opponent_cards: HBoxContainer = $Layout/OpponentArea/Cards

@onready var community_container: HBoxContainer = $Layout/CommunityCards

@onready var my_name_label: Label        = $Layout/MyArea/NameLabel
@onready var my_chips_label: Label       = $Layout/MyArea/ChipsLabel
@onready var my_bet_label: Label         = $Layout/MyArea/BetLabel
@onready var my_cards: HBoxContainer     = $Layout/MyArea/Cards

@onready var action_panel: HBoxContainer = $Layout/ActionPanel
@onready var fold_btn: Button            = $Layout/ActionPanel/FoldBtn
@onready var check_btn: Button           = $Layout/ActionPanel/CheckBtn
@onready var call_btn: Button            = $Layout/ActionPanel/CallBtn
@onready var raise_btn: Button           = $Layout/ActionPanel/RaiseBtn
@onready var raise_slider: HSlider       = $Layout/RaisePanel/RaiseSlider
@onready var raise_panel: HBoxContainer  = $Layout/RaisePanel
@onready var raise_amount_label: Label   = $Layout/RaisePanel/AmountLabel
@onready var confirm_raise_btn: Button   = $Layout/RaisePanel/ConfirmBtn

@onready var result_popup: PanelContainer = $ResultPopup
@ontml var result_label: Label            = $ResultPopup/Label
@onready var next_round_btn: Button      = $ResultPopup/NextRoundBtn

var _my_id: int
var _last_snapshot: Dictionary = {}
var _valid_actions: Array = []
var _current_bet: int = 0

const STAGE_NAMES := {
	GameState.Stage.WAITING:   "Ожидание",
	GameState.Stage.PRE_FLOP:  "Пре-флоп",
	GameState.Stage.FLOP:      "Флоп",
	GameState.Stage.TURN:      "Тёрн",
	GameState.Stage.RIVER:     "Ривер",
	GameState.Stage.SHOWDOWN:  "Вскрытие",
}

func _ready() -> void:
	_my_id = Network.my_id
	raise_panel.visible = false
	result_popup.visible = false
	action_panel.visible = false

	fold_btn.pressed.connect(func(): _send_action(GameState.Action.FOLD))
	check_btn.pressed.connect(func(): _send_action(GameState.Action.CHECK))
	call_btn.pressed.connect(func(): _send_action(GameState.Action.CALL))
	raise_btn.pressed.connect(_on_raise_pressed)
	confirm_raise_btn.pressed.connect(_on_confirm_raise)
	raise_slider.value_changed.connect(func(v): raise_amount_label.text = str(int(v)))
	next_round_btn.pressed.connect(_on_next_round)

	GameManager.state_updated.connect(_on_state_updated)
	GameManager.action_needed.connect(_on_action_needed)
	GameManager.round_result.connect(_on_round_result)
	GameManager.game_over.connect(_on_game_over)

# --- Обновление UI ---

func _on_state_updated(snapshot: Dictionary) -> void:
	_last_snapshot = snapshot
	var players: Array = snapshot["players"]
	var me := _find_player(players, _my_id)
	var opp := _find_opponent(players, _my_id)

	stage_label.text = STAGE_NAMES.get(snapshot["stage"], "")
	pot_label.text   = "Банк: %d" % snapshot["pot"]
	_current_bet     = snapshot["current_bet"]

	if me:
		my_name_label.text  = me["name"]
		my_chips_label.text = "%d фишек" % me["chips"]
		my_bet_label.text   = "Ставка: %d" % me["current_bet"]
	if opp:
		opponent_name.text  = opp["name"]
		opponent_chips.text = "%d фишек" % opp["chips"]
		opponent_bet.text   = "Ставка: %d" % opp["current_bet"]
		_update_opponent_cards(opp)

	_update_community_cards(snapshot["community_cards"])

	var active_id: int = snapshot.get("active_player", -1)
	if active_id != _my_id:
		action_panel.visible = false
		raise_panel.visible  = false

func _on_action_needed(valid_actions: Array) -> void:
	_valid_actions = valid_actions
	action_panel.visible = true
	raise_panel.visible  = false

	fold_btn.disabled  = not GameState.Action.FOLD  in valid_actions
	check_btn.disabled = not GameState.Action.CHECK in valid_actions
	call_btn.disabled  = not GameState.Action.CALL  in valid_actions
	raise_btn.disabled = not GameState.Action.RAISE in valid_actions

	var players: Array = _last_snapshot.get("players", [])
	var me := _find_player(players, _my_id)
	if me:
		var diff := maxi(0, _current_bet - me.get("current_bet", 0))
		call_btn.text = "Колл %d" % diff if diff > 0 else "Колл"
		_setup_raise_slider(me.get("chips", 0), diff)

func _on_round_result(winner_name: String, pot_amount: int, hand_name: String) -> void:
	action_panel.visible = false
	raise_panel.visible  = false
	result_popup.visible = true
	var hand_str := (" — " + hand_name) if hand_name != "" else ""
	result_label.text = "%s выиграл %d фишек%s" % [winner_name, pot_amount, hand_str]
	next_round_btn.visible = Network.is_host

func _on_game_over(winner_name: String) -> void:
	result_popup.visible = true
	result_label.text    = winner_name + " победил в игре!"
	next_round_btn.visible = false

func _on_next_round() -> void:
	result_popup.visible = false
	_clear_cards()
	GameManager._game.start_round()

# --- Карты ---

func _update_community_cards(cards_data: Array) -> void:
	for child in community_container.get_children():
		child.queue_free()
	for cd in cards_data:
		community_container.add_child(_make_card_label(cd["rank"], cd["suit"], true))

func _update_opponent_cards(opp: Dictionary) -> void:
	for child in opponent_cards.get_children():
		child.queue_free()
	# Показываем рубашки для карт оппонента
	for _i in range(2):
		opponent_cards.add_child(_make_back_label())

func _update_my_cards(snapshot: Dictionary) -> void:
	# Карты хранятся только на хосте — он отправляет свои карты только себе
	# Реализация через отдельное сообщение "hole_cards"
	pass

func _clear_cards() -> void:
	for child in community_container.get_children():
		child.queue_free()
	for child in my_cards.get_children():
		child.queue_free()
	for child in opponent_cards.get_children():
		child.queue_free()

func _make_card_label(rank: int, suit: int, _face_up: bool) -> Label:
	var c := Card.new(rank as Card.Rank, suit as Card.Suit)
	var lbl := Label.new()
	lbl.text = c.to_string()
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_color_override("font_color",
		Color(0.85, 0.1, 0.1) if c.is_red() else Color(0.05, 0.05, 0.05))
	lbl.add_theme_stylebox_override("normal", _card_style())
	return lbl

func _make_back_label() -> Label:
	var lbl := Label.new()
	lbl.text = "🂠"
	lbl.add_theme_font_size_override("font_size", 28)
	lbl.add_theme_stylebox_override("normal", _card_style())
	return lbl

func _card_style() -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color      = Color.WHITE
	sb.corner_radius_top_left     = 6
	sb.corner_radius_top_right    = 6
	sb.corner_radius_bottom_left  = 6
	sb.corner_radius_bottom_right = 6
	sb.content_margin_left   = 8
	sb.content_margin_right  = 8
	sb.content_margin_top    = 6
	sb.content_margin_bottom = 6
	return sb

# --- Действия ---

func _send_action(action: GameState.Action, amount: int = 0) -> void:
	action_panel.visible = false
	raise_panel.visible  = false
	GameManager.send_action(action, amount)

func _on_raise_pressed() -> void:
	raise_panel.visible = true

func _on_confirm_raise() -> void:
	_send_action(GameState.Action.RAISE, int(raise_slider.value))

func _setup_raise_slider(my_chips: int, call_diff: int) -> void:
	raise_slider.min_value = GameManager.game_settings.get("big_blind", 20)
	raise_slider.max_value = maxi(my_chips - call_diff, raise_slider.min_value)
	raise_slider.value     = raise_slider.min_value
	raise_amount_label.text = str(int(raise_slider.value))

# --- Вспомогательные ---

func _find_player(players: Array, pid: int) -> Dictionary:
	for p in players:
		if p["id"] == pid:
			return p
	return {}

func _find_opponent(players: Array, pid: int) -> Dictionary:
	for p in players:
		if p["id"] != pid:
			return p
	return {}
