extends Node

signal connected_to_room(room_code: String, my_id: int)
signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal message_received(from_id: int, msg: Dictionary)
signal connection_failed(reason: String)

const STUN_SERVERS := [
	{ "urls": ["stun:stun.l.google.com:19302"] },
	{ "urls": ["stun:stun1.l.google.com:19302"] },
]

var my_id: int = 0
var is_host: bool = false
var room_code: String = ""

var _signaling := SignalingClient.new()
var _peers: Dictionary = {}         # peer_id -> WebRTCPeerConnection
var _channels: Dictionary = {}      # peer_id -> WebRTCDataChannel
var _my_name: String = ""
var _pending_room: String = ""
var _pending_name: String = ""
var _is_joining: bool = false

func _ready() -> void:
	_signaling.connected_to_server.connect(_on_signaling_connected)
	_signaling.disconnected_from_server.connect(_on_signaling_disconnected)
	_signaling.room_joined.connect(_on_room_joined)
	_signaling.peer_joined.connect(_on_peer_joined)
	_signaling.peer_left.connect(_on_peer_left)
	_signaling.offer_received.connect(_on_offer_received)
	_signaling.answer_received.connect(_on_answer_received)
	_signaling.ice_received.connect(_on_ice_received)
	_signaling.error.connect(_on_signaling_error)

func _process(_delta: float) -> void:
	_signaling.poll()
	for peer_id in _channels:
		var ch: WebRTCDataChannel = _channels[peer_id]
		ch.poll()
		while ch.get_available_packet_count() > 0:
			var raw := ch.get_packet()
			var json := JSON.new()
			if json.parse(raw.get_string_from_utf8()) == OK:
				emit_signal("message_received", peer_id, json.get_data())

# --- Публичный API ---

func create_room(code: String, player_name: String) -> void:
	is_host = true
	_my_name = player_name
	_pending_room = code
	_pending_name = player_name
	_signaling.connect_to_server()

func join_room(code: String, player_name: String) -> void:
	is_host = false
	_my_name = player_name
	_pending_room = code
	_pending_name = player_name
	_is_joining = true
	_signaling.connect_to_server()

func send(to_id: int, msg: Dictionary) -> void:
	if _channels.has(to_id):
		var ch: WebRTCDataChannel = _channels[to_id]
		if ch.get_ready_state() == WebRTCDataChannel.STATE_OPEN:
			ch.put_packet(JSON.stringify(msg).to_utf8_buffer())

func broadcast(msg: Dictionary) -> void:
	for peer_id in _channels:
		send(peer_id, msg)

func disconnect_all() -> void:
	for peer_id in _peers:
		_peers[peer_id].close()
	_peers.clear()
	_channels.clear()
	_signaling.disconnect_from_server()

# --- Signaling callbacks ---

func _on_signaling_connected() -> void:
	if _is_joining:
		_signaling.join_room(_pending_room, _pending_name)
	else:
		_signaling.create_room(_pending_room, _pending_name)

func _on_signaling_disconnected() -> void:
	pass

func _on_room_joined(code: String, peer_id: int) -> void:
	my_id = peer_id
	room_code = code
	emit_signal("connected_to_room", code, peer_id)

func _on_peer_joined(peer_id: int, _peer_name: String) -> void:
	var conn := _create_peer(peer_id)
	# Хост инициирует соединение
	if is_host:
		var ch := conn.create_data_channel("game", { "negotiated": true, "id": 1 })
		_channels[peer_id] = ch
		var offer := await conn.create_offer()
		conn.set_local_description(offer)
		_signaling.send_offer(peer_id, { "sdp": offer["sdp"], "type": offer["type"] })

func _on_peer_left(peer_id: int) -> void:
	if _peers.has(peer_id):
		_peers[peer_id].close()
		_peers.erase(peer_id)
	_channels.erase(peer_id)
	emit_signal("peer_disconnected", peer_id)

func _on_offer_received(from_id: int, offer: Dictionary) -> void:
	var conn := _create_peer(from_id)
	var ch := conn.create_data_channel("game", { "negotiated": true, "id": 1 })
	_channels[from_id] = ch
	conn.set_remote_description(offer)
	var answer := await conn.create_answer()
	conn.set_local_description(answer)
	_signaling.send_answer(from_id, { "sdp": answer["sdp"], "type": answer["type"] })

func _on_answer_received(from_id: int, answer: Dictionary) -> void:
	if _peers.has(from_id):
		_peers[from_id].set_remote_description(answer)

func _on_ice_received(from_id: int, candidate: Dictionary) -> void:
	if _peers.has(from_id):
		_peers[from_id].add_ice_candidate(
			candidate["sdpMid"],
			candidate["sdpMLineIndex"],
			candidate["candidate"]
		)

func _on_signaling_error(message: String) -> void:
	emit_signal("connection_failed", message)

# --- Создание WebRTC peer ---

func _create_peer(peer_id: int) -> WebRTCPeerConnection:
	var conn := WebRTCPeerConnection.new()
	conn.initialize({ "iceServers": STUN_SERVERS })
	conn.ice_candidate_created.connect(func(mid, index, sdp):
		_signaling.send_ice(peer_id, { "sdpMid": mid, "sdpMLineIndex": index, "candidate": sdp })
	)
	conn.session_description_created.connect(func(type, sdp):
		conn.set_local_description({ "type": type, "sdp": sdp })
	)
	conn.peer_connected.connect(func():
		emit_signal("peer_connected", peer_id)
	)
	_peers[peer_id] = conn
	return conn
