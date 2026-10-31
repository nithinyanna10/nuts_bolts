class_name MagnetMeshFactory
extends RefCounted
## Low-poly horseshoe magnet from boxes. Arc at the bottom, prongs point along +Y, thickness along Z.
## Surface 0 = red body, surface 1 = silver tips (emissive, driven by the hand script).


static func make(outer_radius: float = 0.07, width: float = 0.035, thickness: float = 0.04,
		prong_length: float = 0.09, tip_length: float = 0.035, arc_segments: int = 8) -> ArrayMesh:
	var body := SurfaceTool.new()
	body.begin(Mesh.PRIMITIVE_TRIANGLES)
	var tips := SurfaceTool.new()
	tips.begin(Mesh.PRIMITIVE_TRIANGLES)

	var mid_r: float = outer_radius - width / 2.0
	var chord: float = 2.0 * mid_r * sin(PI / (2.0 * arc_segments)) * 1.15 # slight overlap hides seams
	for i in arc_segments:
		var theta: float = PI + PI * (i + 0.5) / arc_segments
		var xf := Transform3D(Basis(Vector3.BACK, theta + PI / 2.0), Vector3(cos(theta) * mid_r, sin(theta) * mid_r, 0.0))
		_add_box(body, Vector3(chord, width, thickness), xf)

	var body_len: float = prong_length - tip_length
	for side: float in [-1.0, 1.0]:
		_add_box(body, Vector3(width, body_len, thickness), Transform3D(Basis.IDENTITY, Vector3(side * mid_r, body_len / 2.0, 0.0)))
		_add_box(tips, Vector3(width, tip_length, thickness), Transform3D(Basis.IDENTITY, Vector3(side * mid_r, body_len + tip_length / 2.0, 0.0)))

	var mesh: ArrayMesh = body.commit()
	tips.commit(mesh)

	var red := StandardMaterial3D.new()
	red.albedo_color = Color(0.85, 0.08, 0.08)
	red.metallic = 0.3
	red.roughness = 0.45
	mesh.surface_set_material(0, red)

	var silver := StandardMaterial3D.new()
	silver.albedo_color = Color(0.82, 0.84, 0.88)
	silver.metallic = 0.8
	silver.roughness = 0.3
	silver.emission_enabled = true
	silver.emission = Color(0.45, 0.7, 1.0)
	silver.emission_energy_multiplier = 0.0
	mesh.surface_set_material(1, silver)
	return mesh


static func _add_box(st: SurfaceTool, size: Vector3, xform: Transform3D) -> void:
	var box := BoxMesh.new()
	box.size = size
	st.append_from(box, 0, xform)
