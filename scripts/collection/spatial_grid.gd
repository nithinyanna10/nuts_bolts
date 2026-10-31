class_name SpatialGrid
extends RefCounted
## Uniform hash grid that owns the item positions. Items can be moved and removed, not added.

const EMPTY: Array = []

var cell_size: float = 1.0
var positions := PackedVector3Array()
var _cells: Dictionary = {} ## Vector3i -> Array[int]


func setup(cell: float, items: PackedVector3Array) -> void:
	cell_size = cell
	positions = items
	_cells.clear()
	for id in positions.size():
		_cell_of(positions[id]).append(id)


func remove(id: int) -> void:
	(_cells.get(_key(positions[id]), EMPTY) as Array).erase(id)


func add(id: int, position: Vector3) -> void:
	positions[id] = position
	_cell_of(position).append(id)


func move(id: int, new_position: Vector3) -> void:
	var old_key: Vector3i = _key(positions[id])
	var new_key: Vector3i = _key(new_position)
	if old_key != new_key:
		(_cells.get(old_key, EMPTY) as Array).erase(id)
		positions[id] = new_position
		_cell_of(new_position).append(id)
	else:
		positions[id] = new_position


func query(center: Vector3, radius: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	out.resize(query_into(center, radius, out))
	return out


## Writes ids within radius into out (grown if needed, never shrunk) and returns how many.
func query_into(center: Vector3, radius: float, out: PackedInt32Array) -> int:
	var count: int = 0
	var r2: float = radius * radius
	var lo: Vector3i = _key(center - Vector3.ONE * radius)
	var hi: Vector3i = _key(center + Vector3.ONE * radius)
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				for id: int in _cells.get(Vector3i(x, y, z), EMPTY):
					if positions[id].distance_squared_to(center) <= r2:
						if count == out.size():
							out.resize(maxi(count * 2, 64))
						out[count] = id
						count += 1
	return count


## Ids within a horizontal radius of center, at or below center.y and no more than `below` under it.
## (A sphere would miss a supporter that is far below but close in plan view.)
func query_below(center: Vector3, radius: float, below: float) -> PackedInt32Array:
	var out := PackedInt32Array()
	var lo: Vector3i = _key(Vector3(center.x - radius, center.y - below, center.z - radius))
	var hi: Vector3i = _key(Vector3(center.x + radius, center.y, center.z + radius))
	var r2: float = radius * radius
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				for id: int in _cells.get(Vector3i(x, y, z), EMPTY):
					var p: Vector3 = positions[id]
					if p.y <= center.y and p.y >= center.y - below and (p.x - center.x) * (p.x - center.x) + (p.z - center.z) * (p.z - center.z) <= r2:
						out.append(id)
	return out


## Every id in the 27 cells around a point, no distance filter (for ray marching).
func neighbors_into(point: Vector3, out: PackedInt32Array) -> int:
	var count: int = 0
	var c: Vector3i = _key(point)
	for x in range(c.x - 1, c.x + 2):
		for y in range(c.y - 1, c.y + 2):
			for z in range(c.z - 1, c.z + 2):
				for id: int in _cells.get(Vector3i(x, y, z), EMPTY):
					if count == out.size():
						out.resize(maxi(count * 2, 64))
					out[count] = id
					count += 1
	return count


func nearest(center: Vector3, radius: float) -> int:
	var best: int = -1
	var best_d2: float = INF
	for id in query(center, radius):
		var d2: float = positions[id].distance_squared_to(center)
		if d2 < best_d2:
			best_d2 = d2
			best = id
	return best


func _key(p: Vector3) -> Vector3i:
	return Vector3i((p / cell_size).floor())


func _cell_of(p: Vector3) -> Array:
	var key: Vector3i = _key(p)
	if not _cells.has(key):
		_cells[key] = []
	return _cells[key]
