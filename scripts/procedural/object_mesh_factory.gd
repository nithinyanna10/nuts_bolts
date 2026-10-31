class_name ObjectMeshFactory
extends RefCounted
## Procedural low-poly meshes in mm at ObjDefs.REF_DIAMETER, origin on the head's bearing plane, shaft along -Y.
## Shaft vertices carry UV.x flags so the shader can stretch only the shaft (heads and thread spacing stay true).

const MARK_LIFT: float = 0.12 ## drive marks sit this far above the head top

static var _cache: Dictionary = {}


static func get_mesh(type: int, head: int, drive: int) -> ArrayMesh:
	var key: int = type * 10000 + head * 100 + drive
	if not _cache.has(key):
		_cache[key] = make(type, head, drive)
	return _cache[key]


static func make(type: int, head: int, drive: int) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # flat shading
	match type:
		ObjDefs.Type.SCREW: _screw(st, head, drive)
		ObjDefs.Type.BOLT: _bolt(st, head)
		ObjDefs.Type.NUT: _nut(st, head)
		_: _washer(st, head)
	st.generate_normals()
	return st.commit()


static func _screw(st: SurfaceTool, head: int, drive: int) -> void:
	var top_r: float
	var top_y: float
	match head:
		ObjDefs.Head.PAN:
			_frustum(st, 0.0, 7.0, 2.5, 7.0, 8, true, false)
			_frustum(st, 2.5, 7.0, 4.5, 5.0, 8, false, true)
			top_r = 5.0
			top_y = 4.5
		ObjDefs.Head.FLAT:
			_frustum(st, 0.0, 4.2, 3.5, 8.0, 8, true, true)
			top_r = 8.0
			top_y = 3.5
		_:
			_frustum(st, 0.0, 6.5, 2.0, 6.3, 8, true, false)
			_frustum(st, 2.0, 6.3, 4.0, 4.6, 8, false, false)
			_frustum(st, 4.0, 4.6, 5.0, 3.2, 8, false, true)
			top_r = 3.2
			top_y = 5.0
	_drive_mark(st, drive, top_r, top_y + MARK_LIFT)
	_shaft(st, 0.8)


static func _bolt(st: SurfaceTool, head: int) -> void:
	var sides: int = 6 if head == ObjDefs.Head.HEX else 4
	_frustum(st, 0.0, ObjDefs.head_radius(ObjDefs.Type.BOLT, head), ObjDefs.head_height(ObjDefs.Type.BOLT, head), ObjDefs.head_radius(ObjDefs.Type.BOLT, head), sides, true, true)
	_shaft(st, 3.0)


static func _nut(st: SurfaceTool, head: int) -> void:
	var sides: int = 6 if head == ObjDefs.Head.HEX else 4
	var r: float = ObjDefs.head_radius(ObjDefs.Type.NUT, head)
	var h: float = ObjDefs.head_height(ObjDefs.Type.NUT, head)
	_ring_body(st, r, h, 4.0, sides)


static func _washer(st: SurfaceTool, head: int) -> void:
	_ring_body(st, ObjDefs.head_radius(ObjDefs.Type.WASHER, head), ObjDefs.head_height(ObjDefs.Type.WASHER, head), 4.5, 12)


## Threaded shaft: body (flag 1, stretched) then tip (flag 2, follows the body end).
static func _shaft(st: SurfaceTool, tip_r: float) -> void:
	_frustum(st, 0.0, ObjDefs.SHAFT_R, -ObjDefs.BODY_LEN, ObjDefs.SHAFT_R, 8, false, false, 1.0)
	_frustum(st, -ObjDefs.BODY_LEN, ObjDefs.SHAFT_R, -ObjDefs.BODY_LEN - ObjDefs.TIP_H, tip_r, 8, false, tip_r > 2.0, 2.0)


static func _ring_body(st: SurfaceTool, outer_r: float, h: float, inner_r: float, sides: int) -> void:
	_frustum(st, 0.0, outer_r, h, outer_r, sides, false, false)
	_frustum(st, 0.0, inner_r, h, inner_r, sides, false, false)
	for i in sides:
		var a0: float = TAU * i / sides
		var a1: float = TAU * (i + 1) / sides
		for y: float in [0.0, h]:
			var i0: Vector3 = _p(inner_r, y, a0)
			var i1: Vector3 = _p(inner_r, y, a1)
			var o0: Vector3 = _p(outer_r, y, a0)
			var o1: Vector3 = _p(outer_r, y, a1)
			_tri(st, i0, o0, o1)
			_tri(st, i0, o1, i1)


static func _drive_mark(st: SurfaceTool, drive: int, top_r: float, y: float) -> void:
	var mr: float = top_r * 0.72
	match drive:
		ObjDefs.Drive.PHILLIPS:
			_mark_quad(st, y, Vector2(mr, 0.55), 0.0)
			_mark_quad(st, y, Vector2(mr, 0.55), PI / 2.0)
		ObjDefs.Drive.SLOTTED:
			_mark_quad(st, y, Vector2(top_r * 0.95, 0.8), 0.0)
		ObjDefs.Drive.TORX:
			for i in 12: # six-lobed star
				var r0: float = mr if i % 2 == 0 else mr * 0.6
				var r1: float = mr if i % 2 == 1 else mr * 0.6
				_tri(st, Vector3(0, y, 0), _p(r0, y, TAU * i / 12.0), _p(r1, y, TAU * (i + 1) / 12.0), 0.0, 1.0)
		ObjDefs.Drive.HEX_SOCKET:
			for i in 6:
				_tri(st, Vector3(0, y, 0), _p(mr * 0.85, y, TAU * i / 6.0), _p(mr * 0.85, y, TAU * (i + 1) / 6.0), 0.0, 1.0)


## Flat marked rectangle: half extents (length, width) rotated by angle around the head axis.
static func _mark_quad(st: SurfaceTool, y: float, half: Vector2, angle: float) -> void:
	var b := Basis(Vector3.UP, angle)
	var a: Vector3 = b * Vector3(-half.x, y, -half.y)
	var c: Vector3 = b * Vector3(half.x, y, -half.y)
	var d: Vector3 = b * Vector3(half.x, y, half.y)
	var e: Vector3 = b * Vector3(-half.x, y, half.y)
	_tri(st, a, c, d, 0.0, 1.0)
	_tri(st, a, d, e, 0.0, 1.0)


static func _p(radius: float, y: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, y, sin(angle) * radius)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, flag: float = 0.0, mark: float = 0.0) -> void:
	for v: Vector3 in [a, b, c]:
		st.set_uv(Vector2(flag, mark))
		st.add_vertex(v)


## Frustum between two rings (a radius of 0 makes a cone tip). The shader culls nothing, so winding only affects normals.
static func _frustum(st: SurfaceTool, y0: float, r0: float, y1: float, r1: float, sides: int, cap_bottom: bool, cap_top: bool, flag: float = 0.0) -> void:
	for i in sides:
		var a0: float = TAU * i / sides
		var a1: float = TAU * (i + 1) / sides
		var b0: Vector3 = _p(r0, y0, a0)
		var b1: Vector3 = _p(r0, y0, a1)
		var t0: Vector3 = _p(r1, y1, a0)
		var t1: Vector3 = _p(r1, y1, a1)
		var up: bool = y1 > y0
		if r1 > 0.0:
			_tri(st, t1, t0, b0, flag) if up else _tri(st, t0, t1, b0, flag)
		if r0 > 0.0:
			_tri(st, t1, b0, b1, flag) if up else _tri(st, t0, b0, b1, flag)
		if cap_top:
			_tri(st, Vector3(0.0, y1, 0.0), t0, t1, flag)
		if cap_bottom:
			_tri(st, Vector3(0.0, y0, 0.0), b1, b0, flag)
