class_name Card
extends RefCounted

enum Suit { CLUBS, DIAMONDS, HEARTS, SPADES }
enum Rank { TWO=2, THREE, FOUR, FIVE, SIX, SEVEN, EIGHT, NINE, TEN, JACK, QUEEN, KING, ACE }

var suit: Suit
var rank: Rank

func _init(r: Rank, s: Suit) -> void:
	rank = r
	suit = s

func rank_name() -> String:
	match rank:
		Rank.JACK:  return "J"
		Rank.QUEEN: return "Q"
		Rank.KING:  return "K"
		Rank.ACE:   return "A"
		_:          return str(rank)

func suit_symbol() -> String:
	match suit:
		Suit.CLUBS:    return "♣"
		Suit.DIAMONDS: return "♦"
		Suit.HEARTS:   return "♥"
		Suit.SPADES:   return "♠"
	return ""

func to_string() -> String:
	return rank_name() + suit_symbol()

func is_red() -> bool:
	return suit == Suit.HEARTS or suit == Suit.DIAMONDS
