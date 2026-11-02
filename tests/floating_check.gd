extends RefCounted
## Independent "is anything floating" rule shared by the soak and zero-floating tests.
## Use: const FloatingCheck = preload("res://tests/floating_check.gd")

const SUPPORT_TOL: float = 0.02
const FLOOR_TOL: float = 0.01


## 1 for each active object that rests on nothing. Physical rule, independent of the layout's own: an object is
## supported if it is on the floor, or some lower object touches it in plan view (2D distance between their axis
## segments is below the sum of their radii) with no vertical gap above SUPPORT_TOL.
static func flags(l: PileLayout) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(l.ids.size())
	for k in l.ids.size():
		if l.active[k] == 0:
			continue
		var p: Vector3 = l.grid.positions[k]
		if p.y - l.half_vert[k] <= FLOOR_TOL:
			continue
		var supported: bool = false
		var seg_k: PackedVector2Array = _segment(l, k)
		for m in l.grid.query(p, l.half[k].y + l.max_foot * 2.0 + l.half[k].x):
			var pm: Vector3 = l.grid.positions[m]
			if m == k or pm.y >= p.y:
				continue
			var gap: float = (p.y - l.half_vert[k]) - (pm.y + l.half_vert[m])
			if gap > SUPPORT_TOL:
				continue
			var seg_m: PackedVector2Array = _segment(l, m)
			if _segment_distance(seg_k[0], seg_k[1], seg_m[0], seg_m[1]) < l.half[k].x + l.half[m].x + 0.01:
				supported = true
				break
		out[k] = 0 if supported else 1
	return out


static func _segment(l: PileLayout, k: int) -> PackedVector2Array:
	var c := Vector2(l.grid.positions[k].x, l.grid.positions[k].z)
	var axis := Vector2(l.rot[k].y.x, l.rot[k].y.z) * l.half[k].y
	return PackedVector2Array([c - axis, c + axis])


static func _segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	# Closest distance between two 2D segments (they intersect => 0).
	var best: float = INF
	for pair in [[a0, b0, b1], [a1, b0, b1], [b0, a0, a1], [b1, a0, a1]]:
		var pt: Vector2 = pair[0]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(pt, pair[1], pair[2])
		best = minf(best, pt.distance_to(closest))
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	return best
