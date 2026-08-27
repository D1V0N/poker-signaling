extends Node

signal lobby_ready(players: Array)
signal game_started
signal state_updated(snapshot: Dictionary)
signal action_needed(valid_actions: Array)
signal round_result(winner_name: String, pot: int, hand_name: String)
signal game_over(winner_name: String)

var my_name: String = "Player"
var players_info: Array = []   # [{ id, name }]
var game_settings: Dictionary = {
	"small_blind":    10,
	"big_blind":      20,
	"starting_chips": 1000,
}

var _game: GameState = null

func _ready() -> void:
	Network.peer_connected.connect(_on_peer_connected)
	Network.peer_disconnected.connect(_on_peer_disconnected)
	Network.message_received.connect(_on_message_received)
	Network.connected_to_room.connect(_on_connected_to_room)

# --- Лобби ---

func _on_connected_to_room(_code: String, my_id: int) -> void:
	players_info = [{ "id": my_id, "name": my_name }]

func _on_peer_connected(peer_id: int) -> void:
	if Network.is_host:
		# Отправляем гостю список игроков и настройки
		Network.send(peer_id, {
			"type": "welcome",
			"players": players_info,
			"settings": game_settings,
		})

func _on_peer_disconnected(peer_id: int) -> void:
	players_info = players_info.filter(func(p): return p["id"] != peer_id)

# --- Хост: запускает игру ---

func start_game() -> void:
	assert(Network.is_host)
	Network.broadcast({ "type": "start_game", "players": players_info, "settings": game_settings })
	_init_game(players_info, game_settings)

# --- Действие игрока ---

func send_action(action: GameState.Action, amount: int = 0) -> void:
	if Network.is_host:
		_game.process_action(Network.my_id, action, amount)
	else:
		Network.broadcast({ "type": "action", "action": action, "amount": amount, "from": Network.my_id })

# --- Входящие сообщения ---

func _on_message_received(_from_id: int, msg: Dictionary) -> void:
	match msg.get("type", ""):
		"welcome":
			players_info = msg["players"]
			game_settings = msg["settings"]
			# Добавляем себя в список если нас там нет
			var found := players_info.any(func(p): return p["id"] == Network.my_id)
			if not found:
				players_info.append({ "id": Network.my_id, "name": my_name })
				Network.broadcast({ "type": "player_info", "id": Network.my_id, "name": my_name })
			emit_signal("lobby_ready", players_info)
		"player_info":
			var exists := players_info.any(func(p): return p["id"] == msg["id"])
			if not exists:
				players_info.append({ "id": msg["id"], "name": msg["name"] })
			emit_signal("lobby_ready", players_info)
		"start_game":
			players_info = msg["players"]
			game_settings = msg["settings"]
			_init_game(players_info, game_settings)
		"state":
			emit_signal("state_updated", msg["snapshot"])
		"action":
			if Network.is_host:
				_game.process_action(msg["from"], msg["action"], msg.get("amount", 0))

# --- Инициализация игры (только хост) ---

func _init_game(p_list: Array, settings: Dictionary) -> void:
	_game = GameState.new()
	_game.setup(p_list, settings)
	_game.state_changed.connect(_on_state_changed)
	_game.action_required.connect(_on_action_required)
	_game.round_ended.connect(_on_round_ended)
	_game.game_ended.connect(_on_game_ended)
	emit_signal("game_started")
	_game.start_round()

func _on_state_changed(snapshot: Dictionary) -> void:
	# Хост рассылает снимок всем
	Network.broadcast({ "type": "state", "snapshot": snapshot })
	emit_signal("state_updated", snapshot)

func _on_action_required(player_id: int, valid_actions: Array) -> void:
	if player_id == Network.my_id:
		emit_signal("action_needed", valid_actions)
	else:
		Network.send(player_id, { "type": "your_turn", "valid_actions": valid_actions })

func _on_round_ended(winner_id: int, pot: int, hand_name: String) -> void:
	var winner := players_info.filter(func(p): return p["id"] == winner_id)
	var name := winner[0]["name"] if winner.size() > 0 else "?"
	Network.broadcast({ "type": "round_end", "winner": name, "pot": pot, "hand": hand_name })
	emit_signal("round_result", name, pot, hand_name)

func _on_game_ended(winner_id: int) -> void:
	var winner := players_info.filter(func(p): return p["id"] == winner_id)
	var name := winner[0]["name"] if winner.size() > 0 else "?"
	Network.broadcast({ "type": "game_over", "winner": name })
	emit_signal("game_over", name)
