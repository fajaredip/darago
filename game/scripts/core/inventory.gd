extends Node
## Autoload "Inventory": the bag (30 slots) and the three equipped items.
## Saved together with level and gold by Progress.

signal changed
## Equipped items changed: the player's stats need recomputing.
signal equipment_changed

const SIZE := 30

## Bag items (Dictionaries from ItemDB), in slot order.
var items: Array = []
## slot name -> item Dictionary (missing = empty)
var equipped := {}
var _next_id := 1
var rng := RandomNumberGenerator.new()


func _enter_tree() -> void:
	rng.randomize()


func is_full() -> bool:
	return items.size() >= SIZE


## Puts a new item in the bag. Returns false (and keeps nothing) when it is full.
func add(item: Dictionary) -> bool:
	if is_full():
		return false
	item["id"] = _next_id
	_next_id += 1
	items.append(item)
	_changed(false)
	return true


func find(id: int) -> Dictionary:
	for item in items:
		if int(item["id"]) == id:
			return item
	for slot in equipped:
		if int(equipped[slot]["id"]) == id:
			return equipped[slot]
	return {}


func is_equipped(id: int) -> bool:
	for slot in equipped:
		if int(equipped[slot]["id"]) == id:
			return true
	return false


## Moves a bag item to its equipment slot; the item it replaces goes back to the bag.
func equip(id: int) -> bool:
	var index := _bag_index(id)
	if index < 0:
		return false
	var item: Dictionary = items[index]
	var slot: String = item["slot"]
	items.remove_at(index)
	if equipped.has(slot):
		items.insert(index, equipped[slot])
	equipped[slot] = item
	_changed(true)
	return true


func unequip(slot: String) -> bool:
	if not equipped.has(slot) or is_full():
		return false
	items.append(equipped[slot])
	equipped.erase(slot)
	_changed(true)
	return true


## Sells a bag item for gold. Equipped items must be taken off first.
func sell(id: int) -> int:
	var index := _bag_index(id)
	if index < 0:
		return 0
	var price := ItemDB.sell_price(items[index])
	items.remove_at(index)
	Progress.gold += price
	_changed(false)
	return price


## Tries to enhance an item (bag or equipped). Returns "ok", "fail", "gold" or "max".
## `roll` in 0..1 replaces the random roll (tests).
func enhance(id: int, roll := -1.0) -> String:
	var item := find(id)
	if item.is_empty():
		return "max"
	var chance := ItemDB.enhance_chance(item)
	if chance <= 0.0:
		return "max"
	var cost := ItemDB.enhance_cost(item)
	if Progress.gold < cost:
		return "gold"
	Progress.gold -= cost
	if roll < 0.0:
		roll = rng.randf()
	var ok := roll < chance
	if ok:
		item["enhance"] = int(item["enhance"]) + 1
	_changed(ok and is_equipped(id))
	return "ok" if ok else "fail"


## Sum of the stats of everything equipped.
func equipped_stats() -> Dictionary:
	var total := {}
	for slot in equipped:
		var s := ItemDB.stats(equipped[slot])
		for stat in s:
			total[stat] = int(total.get(stat, 0)) + int(s[stat])
	return total


func clear() -> void:
	items.clear()
	equipped.clear()
	_next_id = 1
	_changed(true)


func serialize() -> Dictionary:
	return {"items": items, "equipped": equipped, "next_id": _next_id}


func deserialize(data: Dictionary) -> void:
	items = []
	for item in data.get("items", []):
		if item is Dictionary:
			items.append(item)
	equipped = {}
	var eq: Dictionary = data.get("equipped", {})
	for slot in eq:
		if slot in ItemDB.SLOTS and eq[slot] is Dictionary:
			equipped[slot] = eq[slot]
	_next_id = maxi(int(data.get("next_id", 1)), 1)
	for item in items + equipped.values():
		_next_id = maxi(_next_id, int(item.get("id", 0)) + 1)


func _bag_index(id: int) -> int:
	for i in items.size():
		if int(items[i]["id"]) == id:
			return i
	return -1


func _changed(gear: bool) -> void:
	Progress.save_file()
	if gear:
		equipment_changed.emit()
	changed.emit()
	Progress.changed.emit()
