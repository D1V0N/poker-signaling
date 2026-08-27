extends Control

@onready var room_code_label: Label    = $VBox/RoomCodeLabel
@onready var players_list: VBoxContainer = $VBox/PlayersList
@onready var start_btn: Button         = $VBox/StartBtn
@onready var status_label: Label       = $VBox/StatusLabel

func _ready() -> void:
	start_btn.visible = Network.is_host
	start_btn.pressed.connect(_on_start)
	GameManager.lobby_ready.connect(_on_lobby_ready)
	GameManager.game_started.connect(_on_game_started)
	room_code_label.text = "Код комнаты: " + Network.room_code
	_refresh_players(GameManager.players_info)

func _on_lobby_ready(players: Array) -> void:
	_refresh_players(players)

func _on_start() -> void:
	if GameManager.players_info.size() < 2:
		status_label.text = "Нужен ещё один игрок!"
		return
	GameManager.start_game()

func _on_game_started() -> void:
	get_tree().change_scene_to_file("res://src/ui/game/GameTable.tscn")

func _refresh_players(players: Array) -> void:
	for child in players_list.get_children():
		child.queue_free()
	for p in players:
		var lbl := Label.new()
		var tag := " (хост)" if p["id"] == GameManager.players_info[0]["id"] else ""
		lbl.text = p["name"] + tag
		lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		players_list.add_child(lbl)
	status_label.text = "Ждём игроков..." if players.size() < 2 else "Все на месте!"
