class_name ScrewMeshFactory
extends RefCounted
## Procedural low-poly screw and bolt meshes. Origin is the mid-point, head toward +Y. Flat shaded.


## Round-headed screw with a pointed tip. ~50 tris.
static func make_screw(length: float = 0.22, head_radius: float = 0.06, shaft_radius: float = 0.022) -> ArrayMesh:
	var st := _begin()
	var half: float = length / 2.0
	var head_h: float = length * 0.16
	var tip_h: float = length * 0.2
	_frustum(st, half - head_h, head_radius, half, head_radius * 0.85, 8, true, true)
	_frustum(st, -half + tip_h, shaft_radius, half - head_h, shaft_radius, 6, false, false)
	_frustum(st, -half, 0.0, -half + tip_h, shaft_radius, 6, false, false)
	return st.commit()


## Hex-headed bolt with a blunt end. ~42 tris.
static func make_bolt(length: float = 0.26, head_radius: float = 0.075, shaft_radius: float = 0.035) -> ArrayMesh:
	var st := _begin()
	var half: float = length / 2.0
	var head_h: float = length * 0.24
	_frustum(st, half - head_h, head_radius, half, head_radius, 6, true, true)
	_frustum(st, -half, shaft_radius, half - head_h, shaft_radius, 6, true, false)
	return st.commit()


static func _begin() -> SurfaceTool:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1) # flat shading
	return st


static func _p(radius: float, y: float, angle: float) -> Vector3:
	return Vector3(cos(angle) * radius, y, sin(angle) * radius)


static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)


## Clockwise (front-facing) frustum between two rings. A radius of 0 makes a cone tip.
static func _frustum(st: SurfaceTool, y0: float, r0: float, y1: float, r1: float, sides: int, cap_bottom: bool, cap_top: bool) -> void:
	for i in sides:
		var a0: float = TAU * i / sides
		var a1: float = TAU * (i + 1) / sides
		var b0: Vector3 = _p(r0, y0, a0)
		var b1: Vector3 = _p(r0, y0, a1)
		var t0: Vector3 = _p(r1, y1, a0)
		var t1: Vector3 = _p(r1, y1, a1)
		if r1 > 0.0:
			_tri(st, t1, t0, b0)
		if r0 > 0.0:
			_tri(st, t1, b0, b1)
		if cap_top:
			_tri(st, Vector3(0.0, y1, 0.0), t0, t1)
		if cap_bottom:
			_tri(st, Vector3(0.0, y0, 0.0), b1, b0)
