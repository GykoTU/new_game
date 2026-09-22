class_name Shop
extends RefCounted
## Buying things: prices, affordability, and what a purchase does.
##
## Prices are resolved through the stat system. Every item has a price
## StatBlock tagged with its price_tags(), and the SHOP_PRICE stat is a
## multiplier on its cost. A sale is therefore just a modifier source --
## "sale:spring" with SHOP_PRICE x0.7 on ["shop", "upgrade"] -- and needs no
## code, saves with the run, and picks up rebalancing like any other modifier.
## An augment can grant a discount the same way.

signal purchased(item: ShopItemData, purchases: int)

## Modifier sources for upgrades are "upg:<item id>". The level is not in the
## id: it is read from purchase counts, so there is one source of truth.
const UPGRADE_PREFIX := "upg:"

var catalogue: ShopCatalogue
## Rules beyond price, such as "a builder needs a free bed". Called with the
## item; returns "" if it may be bought, or the reason it may not.
var purchase_check: Callable

var _economy: Economy
var _roster: WorkerRoster
## Blueprints known this run. Null = everything is known (tests, tools).
var unlocks: Unlocks
## Where crafted buildings go. Required for BUILDING items.
var inventory: BuildingInventory
var _modifiers: ModifierSet
var _price_blocks := {}      # item id -> StatBlock
var _purchases := {}         # item id -> int


func _init(p_catalogue: ShopCatalogue, economy: Economy, roster: WorkerRoster,
		modifiers: ModifierSet) -> void:
	catalogue = p_catalogue
	_economy = economy
	_roster = roster
	_modifiers = modifiers
	for item in catalogue.items:
		if item == null:
			continue
		_price_blocks[item.id] = StatBlock.new(_modifiers, item.price_tags())


func items() -> Array[ShopItemData]:
	return catalogue.items


## How many times this item has been bought this run. For upgrades this IS the
## level. For workers it drives the price, so it counts purchases rather than
## workers alive: losing a worker does not make the next one cheaper.
func purchases_of(item: ShopItemData) -> int:
	return int(_purchases.get(item.id, 0))


func is_maxed(item: ShopItemData) -> bool:
	return item.max_level > 0 and purchases_of(item) >= item.max_level


## The SHOP_PRICE multiplier currently applying to this item. 1.0 = full price.
func price_multiplier(item: ShopItemData) -> float:
	var block: StatBlock = _price_blocks.get(item.id)
	return block.get_value(Stats.Id.SHOP_PRICE) if block != null else 1.0


## Price before any SHOP_PRICE modifier, for showing a struck-through original.
func base_price(item: ShopItemData) -> Dictionary:
	return _price(item, 1.0)


## What the next purchase actually costs.
func price(item: ShopItemData) -> Dictionary:
	return _price(item, price_multiplier(item))


func is_discounted(item: ShopItemData) -> bool:
	return price(item) != base_price(item)


## Why this item cannot be bought right now, apart from price; "" if it can.
## Price is left out on purpose: the shop shows that as red numbers already.
func block_reason(item: ShopItemData) -> String:
	if not is_known(item):
		return "Needs a blueprint"
	if item.kind == ShopItemData.Kind.BUILDING and inventory == null:
		return "Nowhere to keep buildings"
	if item.kind == ShopItemData.Kind.ITEM and unlocks == null:
		return "Nowhere to keep items"
	if is_maxed(item):
		return "Max level"
	if purchase_check.is_valid():
		return purchase_check.call(item)
	return ""


## True if the run knows this item's blueprint (or it needs none). The Craft
## tab hides items that are not known.
func is_known(item: ShopItemData) -> bool:
	return unlocks == null or unlocks.has(item.blueprint)


func can_buy(item: ShopItemData) -> bool:
	return block_reason(item) == "" and _economy.can_afford(price(item))


## Spends the price and applies the item. Returns false and changes nothing if
## the item is maxed or unaffordable.
func buy(item: ShopItemData) -> bool:
	if block_reason(item) != "":
		return false
	if not _economy.spend(price(item)):
		return false
	var n := purchases_of(item) + 1
	_purchases[item.id] = n
	match item.kind:
		ShopItemData.Kind.WORKER:
			_roster.add(item.worker_kind, 1)
		ShopItemData.Kind.UPGRADE:
			# Re-adding the source replaces it, so level 3 replaces level 2.
			_modifiers.add_source(UPGRADE_PREFIX + item.id, item.modifiers_at(n))
		ShopItemData.Kind.BUILDING:
			inventory.add(item.building_id)
		ShopItemData.Kind.ITEM:
			unlocks.add("item:" + item.item_id)
	purchased.emit(item, n)
	return true


## Rebuilds an upgrade's modifiers from current data when a run loads.
## Returns Array[StatModifier], or null if this is not an upgrade source or the
## item no longer exists. Purchases must be loaded before this is called.
func resolve_source(source: String) -> Variant:
	if not source.begins_with(UPGRADE_PREFIX):
		return null
	var item := catalogue.find(source.substr(UPGRADE_PREFIX.length()))
	if item == null or item.kind != ShopItemData.Kind.UPGRADE:
		return null
	return item.modifiers_at(purchases_of(item))


# --- Pricing ------------------------------------------------------------------

## price = round(base * growth^purchases * multiplier), never below 1.
## Rounded, not rounded up: rounding up would make a 30% sale on a 3-gold item
## cost 3 -- no discount at all -- which reads as a bug to a player.
## Halves round up, AFTER snapping away floating-point noise: 45 * 0.7 is
## 31.499999999999996 in binary floating point and would otherwise show 31.
func _price(item: ShopItemData, multiplier: float) -> Dictionary:
	var out := {}
	var growth := pow(item.cost_growth, purchases_of(item))
	for kind in item.base_cost:
		var base := int(item.base_cost[kind])
		if base <= 0:
			continue
		out[kind] = maxi(roundi(snappedf(base * growth * multiplier, 0.001)), 1)
	return out


# --- Saving -------------------------------------------------------------------

## Forgets every purchase. For starting a new run; modifiers are cleared separately.
func reset() -> void:
	_purchases.clear()


func get_save_data() -> Dictionary:
	return {"purchases": _purchases.duplicate()}


## Returns false if the save names an item this build does not sell.
func load_save_data(data: Dictionary) -> bool:
	_purchases.clear()
	var saved: Dictionary = data.get("purchases", {})
	var unknown := PackedStringArray()
	for item_id in saved:
		if catalogue.find(item_id) == null:
			unknown.append(item_id)
			continue
		_purchases[item_id] = int(saved[item_id])
	if not unknown.is_empty():
		push_error("Shop: save names items this build does not sell: %s" % ", ".join(unknown))
		return false
	return true
