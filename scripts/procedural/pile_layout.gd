class_name PileLayout
extends RefCounted
## Pure-data heap for one pile. Objects are dropped one by one onto a height field (no physics), so they
## stack and the target can end up under others. remove_and_settle() lowers whatever rested on a removed object.
## Local index j <-> global object id ids[j]. All positions are pile-local meters.

const CELL: float = 0.025 ## height field resolution (must be finer than the thinnest object)
const PACK: float = 0.85 ## how tightly lying objects nest vertically
const SUPPORT_OVERLAP: float = 0.8 ## fraction of summed footprints that counts as "resting on"
const DROP_TRIES: int = 8 ## candidate spots tried before settling for the lowest one

var ids := PackedInt32Array()
var rot: Array[Basis] = []
var half := PackedVector3Array() ## OBB half extents (radial, axial, radial)
var axial_center := PackedFloat32Array() ## OBB center offset along the object's +Y from its origin
var half_vert := PackedFloat32Array() ## vertical half extent when resting
var foot := PackedFloat32Array() ## horizontal footprint radius for support tests
var active := PackedByteArray()
var grid := SpatialGrid.new() ## owns the OBB centers
var radius: float = 0.0
var max_foot: float = 0.0


func build(data: RoundData, pile_index: int, rng: RandomNumberGenerator) -> void:
	var cfg: DifficultyConfig = data.config
	ids = data.pile_objects[pile_index]
	var n: int = ids.size()
	half.resize(n)
	axial_center.resize(n)
	half_vert.resize(n)
	foot.resize(n)
	active.resize(n)
	active.fill(1)
	rot.resize(n)

	var volume: float = 0.0
	for j in n:
		var b: Vector3 = _bounds(data, ids[j], cfg.units_per_mm)
		var long: bool = ObjDefs.has_length(data.cols[ObjDefs.Prop.TYPE][ids[j]])
		half[j] = Vector3(b.x, b.y, b.x)
		axial_center[j] = b.z
		half_vert[j] = b.x * PACK if long else b.y
		foot[j] = b.y * 0.5 + b.x if long else b.x
		volume += 8.0 * b.x * b.x * b.y if long else 2.0 * PI * b.x * b.x * b.y
		max_foot = maxf(max_foot, foot[j])
	# A cone of slope s and radius R holds PI/3 * s * R^3; only pile_packing of that is object.
	radius = pow(volume / (PI / 3.0 * cfg.pile_slope * cfg.pile_packing), 1.0 / 3.0) * cfg.pile_spread

	var size: int = int(ceil((radius + max_foot * 2.0 + 0.5) * 2.0 / CELL)) + 2
	var heights := PackedFloat32Array()
	heights.resize(size * size)
	var centers := PackedVector3Array()
	centers.resize(n)
	for j in n:
		var type: int = data.cols[ObjDefs.Prop.TYPE][ids[j]]
		var long: bool = ObjDefs.has_length(type)
		var yaw: float = rng.randf() * TAU
		var tilt: float = rng.randf_range(-0.25, 0.25)
		var basis: Basis
		if long: # lying on its side: local +Y becomes horizontal
			basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt) * Basis(Vector3.RIGHT, PI / 2.0) * Basis(Vector3.UP, rng.randf() * TAU)
		else:
			basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, tilt * 0.6 + (PI if rng.randf() < 0.5 else 0.0))
		rot[j] = basis

		var axis := Vector2(basis.y.x, basis.y.z)
		var along: Vector2 = axis.normalized() if (long and axis.length() > 0.001) else Vector2.ZERO
		var steps: int = int(ceil(2.0 * half[j].y / CELL)) + 1 if long else 1
		# Try a few spots; take the first that keeps the mound under its repose cone, else the lowest.
		var px: float = 0.0
		var pz: float = 0.0
		var base: float = 0.0
		var best_excess: float = INF
		for attempt in DROP_TRIES:
			var rr: float = radius * pow(rng.randf(), cfg.pile_center_bias)
			var ang: float = rng.randf() * TAU
			var cx: float = cos(ang) * rr
			var cz: float = sin(ang) * rr
			var peak: float = 0.0
			var sum: float = 0.0
			for s in steps:
				var t: float = _step_offset(half[j].y, s, steps)
				var hs: float = _max_height(heights, size, cx + along.x * t, cz + along.y * t, half[j].x)
				peak = maxf(peak, hs)
				sum += hs
			var rest: float = (peak + sum / steps) * 0.5 # rides between the highest support and the average
			var excess: float = rest - cfg.pile_slope * (radius * 1.15 - rr)
			if excess < best_excess:
				best_excess = excess
				px = cx
				pz = cz
				base = rest
			if excess <= 0.04:
				break
		var yc: float = base + half_vert[j]
		for s in steps:
			var t: float = _step_offset(half[j].y, s, steps)
			_raise(heights, size, px + along.x * t, pz + along.y * t, half[j].x, yc + half_vert[j])
		centers[j] = Vector3(px, yc, pz)
	grid.setup(cfg.grid_cell_size, centers)


## World-space-free origin of object j (its mesh origin, the head's bearing plane center).
func origin_of(j: int, center: Vector3) -> Vector3:
	return center - rot[j] * Vector3(0.0, axial_center[j], 0.0)


## Removes object j; whatever rested on it (directly or through a chain) drops. Returns the moved local indices.
func remove_and_settle(j: int) -> PackedInt32Array:
	active[j] = 0
	var removed: Vector3 = grid.positions[j]
	grid.remove(j)
	var queue := PackedInt32Array()
	var moved := PackedInt32Array()
	_queue_resting_on(removed, foot[j], removed.y, queue)
	while not queue.is_empty():
		var qi: int = 0 # always settle the lowest pending object first
		for q in queue.size():
			if grid.positions[queue[q]].y < grid.positions[queue[qi]].y:
				qi = q
		var k: int = queue[qi]
		queue.remove_at(qi)
		var pk: Vector3 = grid.positions[k]
		var new_y: float = half_vert[k]
		for m in grid.query(pk, foot[k] + max_foot):
			var pm: Vector3 = grid.positions[m]
			if m != k and pm.y < pk.y and Vector2(pm.x - pk.x, pm.z - pk.z).length() < (foot[k] + foot[m]) * SUPPORT_OVERLAP:
				new_y = maxf(new_y, pm.y + half_vert[m] + half_vert[k])
		if new_y < pk.y - 0.003:
			grid.move(k, Vector3(pk.x, new_y, pk.z))
			if not moved.has(k):
				moved.append(k)
			_queue_resting_on(pk, foot[k], pk.y, queue)
	return moved


func _queue_resting_on(center: Vector3, f: float, old_y: float, queue: PackedInt32Array) -> void:
	for m in grid.query(center, f + max_foot):
		var pm: Vector3 = grid.positions[m]
		if pm.y > old_y and not queue.has(m) and Vector2(pm.x - center.x, pm.z - center.z).length() < (f + foot[m]) * SUPPORT_OVERLAP:
			queue.append(m)


func _step_offset(half_len: float, s: int, steps: int) -> float:
	return 0.0 if steps == 1 else -half_len + 2.0 * half_len * s / (steps - 1)


func _bounds(data: RoundData, g: int, upm: float) -> Vector3:
	var c: Array[PackedInt32Array] = data.cols
	return ObjDefs.bounds_mm(c[ObjDefs.Prop.TYPE][g], c[ObjDefs.Prop.HEAD][g], c[ObjDefs.Prop.LENGTH_MM][g], c[ObjDefs.Prop.DIAMETER][g]) * upm


func _max_height(heights: PackedFloat32Array, size: int, x: float, z: float, r: float) -> float:
	var best: float = 0.0
	var half_size: float = size * CELL * 0.5
	var cx: int = int((x + half_size) / CELL)
	var cz: int = int((z + half_size) / CELL)
	var reach: int = int(ceil(r / CELL))
	for ix in range(maxi(cx - reach, 0), mini(cx + reach + 1, size)):
		var dx: float = (ix + 0.5) * CELL - half_size - x
		for iz in range(maxi(cz - reach, 0), mini(cz + reach + 1, size)):
			var dz: float = (iz + 0.5) * CELL - half_size - z
			if dx * dx + dz * dz <= r * r:
				best = maxf(best, heights[ix * size + iz])
	return best


func _raise(heights: PackedFloat32Array, size: int, x: float, z: float, r: float, top: float) -> void:
	var half_size: float = size * CELL * 0.5
	var cx: int = int((x + half_size) / CELL)
	var cz: int = int((z + half_size) / CELL)
	var reach: int = int(ceil(r / CELL))
	for ix in range(maxi(cx - reach, 0), mini(cx + reach + 1, size)):
		var dx: float = (ix + 0.5) * CELL - half_size - x
		for iz in range(maxi(cz - reach, 0), mini(cz + reach + 1, size)):
			var dz: float = (iz + 0.5) * CELL - half_size - z
			if dx * dx + dz * dz <= r * r:
				heights[ix * size + iz] = maxf(heights[ix * size + iz], top)
