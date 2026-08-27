extends Control

@onready var name_input: LineEdit       = $VBox/NameInput
@onready var room_input: LineEdit       = $VBox/RoomInput
@onready var create_btn: Button         = $VBox/CreateBtn
@onready var join_btn: Button           = $VBox/JoinBtn
@onready var status_label: Label        = $VBox/StatusLabel

func _ready() -> void:
	create_btn.pressed.connect(_on_create)
	join_btn.pressed.connect(_on_join)
	Network.connection_failed.connect(_on_error)
	Network.connected_to_room.connect(_on_connected)

func _on_create() -> void:
	if not _validate(): return
	var code := room_input.text.strip_edges().to_upper()
	if code.is_empty():
		code = _random_code()
		room_input.text = code
	GameManager.my_name = name_input.text.strip_edges()
	_set_loading(true)
	Network.create_room(code, GameManager.my_name)

func _on_join() -> void:
	if not _validate(): return
	var code := room_input.text.strip_edges().to_upper()
	if code.is_empty():
		status_label.text = "Введи код комнаты"
		return
	GameManager.my_name = name_input.text.strip_edges()
	_set_loading(true)
	Network.join_room(code, GameManager.my_name)

func _on_connected(_code: String, _id: int) -> void:
	get_tree().change_scene_to_file("res://src/ui/lobby/Lobby.tscn")

func _on_error(reason: String) -> void:
	_set_loading(false)
	status_label.text = "Ошибка: " + reason

func _validate() -> bool:
	if name_input.text.strip_edges().is_empty():
		status_label.text = "Введи своё имя"
		return false
	return true

func _set_loading(loading: bool) -> void:
	create_btn.disabled = loading
	join_btn.disabled   = loading
	status_label.text   = "Подключение..." if loading else ""

func _random_code() -> String:
	const CHARS := "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
	var result := ""
	for _i in range(4):
		result += CHARS[randi() % CHARS.length()]
	return result
