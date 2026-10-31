class_name SpatialGrid
extends RefCounted
## Uniform hash grid over a fixed position array. Items can be removed, not added.

const EMPTY: Array = []

var _cell_size: float = 1.0
var _positions: PackedVector3Array
var _cells: Dictionary = {} ## Vector3i -> Array[int]


func setup(cell_size: float, positions: PackedVector3Array) -> void:
	_cell_size = cell_size
	_positions = positions
	_cells.clear()
	for id in positions.size():
		var key: Vector3i = _key(positions[id])
		if not _cells.has(key):
			_cells[key] = []
		(_cells[key] as Array).append(id)


func remove(id: int) -> void:
	var cell: Array = _cells.get(_key(_positions[id]), EMPTY)
	cell.erase(id)


func query(center: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var r2: float = radius * radius
	var lo: Vector3i = _key(center - Vector3.ONE * radius)
	var hi: Vector3i = _key(center + Vector3.ONE * radius)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				for id: int in _cells.get(Vector3i(x, y, z), EMPTY):
					if _positions[id].distance_squared_to(center) <= r2:
						out.append(id)
	return out


## Id of the closest item within radius, or -1.
func nearest(center: Vector3, radius: float) -> int:
	var best: int = -1
	var best_d2: float = INF
	for id in query(center, radius):
		var d2: float = _positions[id].distance_squared_to(center)
		if d2 < best_d2:
			best_d2 = d2
			best = id
	return best


func _key(p: Vector3) -> Vector3i:
	return Vector3i((p / _cell_size).floor())
