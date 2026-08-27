class_name SignalingClient
extends RefCounted

signal connected_to_server
signal disconnected_from_server
signal offer_received(from_id: int, offer: Dictionary)
signal answer_received(from_id: int, answer: Dictionary)
signal ice_received(from_id: int, candidate: Dictionary)
signal room_joined(room_code: String, peer_id: int)
signal peer_joined(peer_id: int, peer_name: String)
signal peer_left(peer_id: int)
signal error(message: String)

# Замени на URL своего сервера на Glitch.com после деплоя
const SERVER_URL := "wss://your-poker-app.glitch.me"

var _ws := WebSocketPeer.new()
var _my_id: int = 0
var _connected: bool = false

func connect_to_server() -> void:
	_ws.connect_to_url(SERVER_URL)

func disconnect_from_server() -> void:
	_ws.close()
	_connected = false

func is_connected_to_server() -> bool:
	return _connected

# Вызывать каждый кадр из Network.gd
func poll() -> void:
	_ws.poll()
	var state := _ws.get_ready_state()
	match state:
		WebSocketPeer.STATE_OPEN:
			if not _connected:
				_connected = true
				emit_signal("connected_to_server")
			while _ws.get_available_packet_count() > 0:
				var raw := _ws.get_packet()
				_handle_message(raw.get_string_from_utf8())
		WebSocketPeer.STATE_CLOSED:
			if _connected:
				_connected = false
				emit_signal("disconnected_from_server")

func create_room(room_code: String, player_name: String) -> void:
	_send({ "type": "create_room", "room": room_code, "name": player_name })

func join_room(room_code: String, player_name: String) -> void:
	_send({ "type": "join_room", "room": room_code, "name": player_name })

func send_offer(to_id: int, offer: Dictionary) -> void:
	_send({ "type": "offer", "to": to_id, "data": offer })

func send_answer(to_id: int, answer: Dictionary) -> void:
	_send({ "type": "answer", "to": to_id, "data": answer })

func send_ice(to_id: int, candidate: Dictionary) -> void:
	_send({ "type": "ice", "to": to_id, "data": candidate })

# --- Приватные ---

func _send(msg: Dictionary) -> void:
	var json := JSON.stringify(msg)
	_ws.send_text(json)

func _handle_message(raw: String) -> void:
	var json := JSON.new()
	if json.parse(raw) != OK:
		return
	var msg: Dictionary = json.get_data()
	match msg.get("type", ""):
		"welcome":
			_my_id = msg["id"]
			emit_signal("room_joined", msg.get("room", ""), _my_id)
		"peer_joined":
			emit_signal("peer_joined", msg["id"], msg["name"])
		"peer_left":
			emit_signal("peer_left", msg["id"])
		"offer":
			emit_signal("offer_received", msg["from"], msg["data"])
		"answer":
			emit_signal("answer_received", msg["from"], msg["data"])
		"ice":
			emit_signal("ice_received", msg["from"], msg["data"])
		"error":
			emit_signal("error", msg.get("message", "Unknown error"))
