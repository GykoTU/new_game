class_name ShopCatalogue
extends Resource
## Everything the shop sells, in display order.
##
## An explicit list rather than scanning a folder: display order is a design
## decision, and exported builds rename resource files, which makes folder
## scanning fragile.

@export var items: Array[ShopItemData] = []


func find(item_id: String) -> ShopItemData:
	for item in items:
		if item != null and item.id == item_id:
			return item
	return null
