class_name MetaTree
extends Resource
## Every node of the relic tree (Stage 8). data/meta/tree.tres.

@export var nodes: Array[MetaNodeData] = []


func find(id: String) -> MetaNodeData:
	for n in nodes:
		if n != null and n.id == id:
			return n
	return null
