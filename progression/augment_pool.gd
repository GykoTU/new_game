class_name AugmentPool
extends Resource
## Every augment in the game, in a stable order (like ShopCatalogue).

@export var items: Array[AugmentData] = []


func find(augment_id: String) -> AugmentData:
	for a in items:
		if a != null and a.id == augment_id:
			return a
	return null
