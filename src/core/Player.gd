class_name Player
extends RefCounted

var id: int          # peer id в сети
var name: String
var chips: int
var hole_cards: Array[Card] = []
var current_bet: int = 0
var is_folded: bool = false
var is_all_in: bool = false

func _init(peer_id: int, player_name: String, starting_chips: int) -> void:
	id = peer_id
	name = player_name
	chips = starting_chips

func reset_for_round() -> void:
	hole_cards.clear()
	current_bet = 0
	is_folded = false
	is_all_in = false

func can_act() -> bool:
	return not is_folded and not is_all_in

func place_bet(amount: int) -> int:
	var actual := mini(amount, chips)
	chips -= actual
	current_bet += actual
	if chips == 0:
		is_all_in = true
	return actual

func to_dict() -> Dictionary:
	return {
		"id":          id,
		"name":        name,
		"chips":       chips,
		"current_bet": current_bet,
		"is_folded":   is_folded,
		"is_all_in":   is_all_in,
	}
