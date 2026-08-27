class_name HandEvaluator
extends RefCounted

enum HandRank {
	HIGH_CARD,
	ONE_PAIR,
	TWO_PAIR,
	THREE_OF_A_KIND,
	STRAIGHT,
	FLUSH,
	FULL_HOUSE,
	FOUR_OF_A_KIND,
	STRAIGHT_FLUSH,
	ROYAL_FLUSH
}

const HAND_NAMES := {
	HandRank.HIGH_CARD:       "Старшая карта",
	HandRank.ONE_PAIR:        "Пара",
	HandRank.TWO_PAIR:        "Две пары",
	HandRank.THREE_OF_A_KIND: "Тройка",
	HandRank.STRAIGHT:        "Стрит",
	HandRank.FLUSH:           "Флэш",
	HandRank.FULL_HOUSE:      "Фулл-хаус",
	HandRank.FOUR_OF_A_KIND:  "Каре",
	HandRank.STRAIGHT_FLUSH:  "Стрит-флэш",
	HandRank.ROYAL_FLUSH:     "Роял-флэш"
}

# Возвращает словарь { rank: HandRank, tiebreakers: Array[int] }
# Принимает 7 карт (2 в руке + 5 общих), возвращает лучшую пятёрку
static func evaluate(cards: Array) -> Dictionary:
	assert(cards.size() >= 5)
	var best: Dictionary = {}
	var combos := _combinations(cards, 5)
	for combo in combos:
		var result := _eval5(combo)
		if best.is_empty() or _compare(result, best) > 0:
			best = result
	return best

static func hand_name(rank: HandRank) -> String:
	return HAND_NAMES.get(rank, "?")

# Сравнивает два результата evaluate(). Возвращает 1, -1 или 0
static func compare(a: Dictionary, b: Dictionary) -> int:
	return _compare(a, b)

# --- Приватные методы ---

static func _eval5(cards: Array) -> Dictionary:
	var ranks: Array[int] = []
	var suits: Array[int] = []
	for c in cards:
		ranks.append(c.rank as int)
		suits.append(c.suit as int)
	ranks.sort()
	ranks.reverse()

	var is_flush := suits.count(suits[0]) == 5
	var is_straight := _check_straight(ranks)
	var straight_high := _straight_high(ranks)

	var freq := _rank_frequency(ranks)
	var counts: Array[int] = freq.values()
	counts.sort()
	counts.reverse()

	var hand_rank: HandRank
	var tiebreakers: Array[int] = []

	if is_straight and is_flush:
		if straight_high == Card.Rank.ACE:
			hand_rank = HandRank.ROYAL_FLUSH
		else:
			hand_rank = HandRank.STRAIGHT_FLUSH
		tiebreakers = [straight_high]
	elif counts[0] == 4:
		hand_rank = HandRank.FOUR_OF_A_KIND
		tiebreakers = _tiebreakers_by_freq(freq, [4, 1])
	elif counts[0] == 3 and counts[1] == 2:
		hand_rank = HandRank.FULL_HOUSE
		tiebreakers = _tiebreakers_by_freq(freq, [3, 2])
	elif is_flush:
		hand_rank = HandRank.FLUSH
		tiebreakers = ranks
	elif is_straight:
		hand_rank = HandRank.STRAIGHT
		tiebreakers = [straight_high]
	elif counts[0] == 3:
		hand_rank = HandRank.THREE_OF_A_KIND
		tiebreakers = _tiebreakers_by_freq(freq, [3, 1, 1])
	elif counts[0] == 2 and counts[1] == 2:
		hand_rank = HandRank.TWO_PAIR
		tiebreakers = _tiebreakers_by_freq(freq, [2, 2, 1])
	elif counts[0] == 2:
		hand_rank = HandRank.ONE_PAIR
		tiebreakers = _tiebreakers_by_freq(freq, [2, 1, 1, 1])
	else:
		hand_rank = HandRank.HIGH_CARD
		tiebreakers = ranks

	return { "rank": hand_rank, "tiebreakers": tiebreakers }

static func _check_straight(sorted_ranks: Array[int]) -> bool:
	# Обычный стрит
	var straight := true
	for i in range(1, sorted_ranks.size()):
		if sorted_ranks[i - 1] - sorted_ranks[i] != 1:
			straight = false
			break
	if straight:
		return true
	# Стрит A-2-3-4-5 (колесо)
	var wheel := [14, 5, 4, 3, 2]
	return sorted_ranks == wheel

static func _straight_high(sorted_ranks: Array[int]) -> int:
	var wheel := [14, 5, 4, 3, 2]
	if sorted_ranks == wheel:
		return 5
	return sorted_ranks[0]

static func _rank_frequency(ranks: Array[int]) -> Dictionary:
	var freq := {}
	for r in ranks:
		freq[r] = freq.get(r, 0) + 1
	return freq

static func _tiebreakers_by_freq(freq: Dictionary, order: Array) -> Array[int]:
	var groups: Array = []
	for count in order:
		for rank in freq:
			if freq[rank] == count and rank not in groups:
				groups.append(rank)
				break
	# Сортируем каждую группу по убыванию ранга внутри одинаковых count
	var result: Array[int] = []
	var seen := {}
	for target_count in order:
		var group: Array[int] = []
		for rank in freq:
			if freq[rank] == target_count and rank not in seen:
				group.append(rank)
		group.sort()
		group.reverse()
		for r in group:
			result.append(r)
			seen[r] = true
	return result

static func _compare(a: Dictionary, b: Dictionary) -> int:
	if a["rank"] != b["rank"]:
		return 1 if a["rank"] > b["rank"] else -1
	var ta: Array = a["tiebreakers"]
	var tb: Array = b["tiebreakers"]
	for i in range(mini(ta.size(), tb.size())):
		if ta[i] != tb[i]:
			return 1 if ta[i] > tb[i] else -1
	return 0

static func _combinations(arr: Array, k: int) -> Array:
	var result := []
	var combo := []
	_combo_helper(arr, k, 0, combo, result)
	return result

static func _combo_helper(arr: Array, k: int, start: int, combo: Array, result: Array) -> void:
	if combo.size() == k:
		result.append(combo.duplicate())
		return
	for i in range(start, arr.size()):
		combo.append(arr[i])
		_combo_helper(arr, k, i + 1, combo, result)
		combo.pop_back()
