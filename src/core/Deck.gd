class_name Deck
extends RefCounted

var _cards: Array[Card] = []

func _init() -> void:
	reset()

func reset() -> void:
	_cards.clear()
	for suit in Card.Suit.values():
		for rank in Card.Rank.values():
			_cards.append(Card.new(rank, suit))

func shuffle() -> void:
	_cards.shuffle()

func deal() -> Card:
	assert(_cards.size() > 0, "Deck is empty")
	return _cards.pop_back()

func remaining() -> int:
	return _cards.size()
