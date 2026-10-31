class_name WarehouseBuilder
extends Node3D
## Builds the warehouse shell, pillars, lights and floor markings from primitives.

@export_group("Room")
@export var room_size: Vector3 = Vector3(40.0, 9.0, 60.0) ## x width, y height, z length
@export var wall_thickness: float = 0.5
@export var beam_spacing: float = 6.0

@export_group("Pillars")
@export var pillar_columns: int = 3
@export var pillar_rows: int = 4
@export var pillar_spacing: Vector2 = Vector2(12.0, 14.0)
@export var pillar_size: float = 0.9
@export var pillar_band_height: float = 0.35
@export var pillar_band_y: float = 1.2

@export_group("Lights")
@export var light_columns: int = 2
@export var light_rows: int = 4
@export var light_spacing: Vector2 = Vector2(12.0, 14.0)
@export var light_color: Color = Color(1.0, 0.78, 0.5)
@export var light_energy: float = 7.0
@export var light_range: float = 20.0
@export var light_angle_deg: float = 60.0
@export var lamp_drop: float = 0.8

@export_group("Floor markings")
@export var stripe_width: float = 0.25
@export var stripe_inset: float = 1.2
@export var dash_length: float = 1.6
@export var dash_gap: float = 1.4
@export var lane_x: float = 6.0

@export_group("Colors")
@export var floor_color: Color = Color(0.42, 0.42, 0.43)
@export var wall_color: Color = Color(0.32, 0.32, 0.34)
@export var pillar_color: Color = Color(0.5, 0.5, 0.5)
@export var steel_color: Color = Color(0.12, 0.12, 0.14)
@export var stripe_color: Color = Color(0.95, 0.75, 0.05)

var _floor_mat: StandardMaterial3D
var _wall_mat: StandardMaterial3D
var _pillar_mat: StandardMaterial3D
var _steel_mat: StandardMaterial3D
var _stripe_mat: StandardMaterial3D
var _bulb_mat: StandardMaterial3D


func _ready() -> void:
	_make_materials()
	_build_shell()
	_build_pillars()
	_build_lights()
	_build_markings()


func _make_materials() -> void:
	_floor_mat = _concrete(floor_color, 0.2)
	_wall_mat = _concrete(wall_color, 0.15)
	_pillar_mat = _concrete(pillar_color, 0.3)
	_steel_mat = _plain(steel_color, 0.5, 0.6)
	_stripe_mat = _plain(stripe_color, 0.6, 0.0)
	_bulb_mat = _plain(light_color, 0.5, 0.0)
	_bulb_mat.emission_enabled = true
	_bulb_mat.emission = light_color
	_bulb_mat.emission_energy_multiplier = 4.0


func _plain(color: Color, roughness: float, metallic: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.roughness = roughness
	m.metallic = metallic
	return m


## Concrete = tinted material with subtle world-space triplanar noise mottling.
func _concrete(color: Color, uv_scale: float) -> StandardMaterial3D:
	var ramp := Gradient.new()
	ramp.colors = PackedColorArray([Color(0.7, 0.7, 0.7), Color.WHITE])
	ramp.offsets = PackedFloat32Array([0.0, 1.0])
	var tex := NoiseTexture2D.new()
	tex.noise = FastNoiseLite.new()
	tex.color_ramp = ramp
	tex.seamless = true
	tex.width = 512
	tex.height = 512
	var m := _plain(color, 0.92, 0.0)
	m.albedo_texture = tex
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE * uv_scale
	return m


func _box(pos: Vector3, size: Vector3, mat: Material, solid: bool = true, casts_shadow: bool = true) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	if not casts_shadow:
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	add_child(mi)
	return mi


func _build_shell() -> void:
	var w: float = room_size.x
	var h: float = room_size.y
	var l: float = room_size.z
	var t: float = wall_thickness
	_box(Vector3(0, -t / 2, 0), Vector3(w + 2 * t, t, l + 2 * t), _floor_mat)
	_box(Vector3(0, h + t / 2, 0), Vector3(w + 2 * t, t, l + 2 * t), _wall_mat)
	_box(Vector3(-(w + t) / 2, h / 2, 0), Vector3(t, h, l + 2 * t), _wall_mat)
	_box(Vector3((w + t) / 2, h / 2, 0), Vector3(t, h, l + 2 * t), _wall_mat)
	_box(Vector3(0, h / 2, -(l + t) / 2), Vector3(w, h, t), _wall_mat)
	_box(Vector3(0, h / 2, (l + t) / 2), Vector3(w, h, t), _wall_mat)
	# Ceiling beams (visual only).
	var z: float = -l / 2 + beam_spacing / 2
	while z < l / 2:
		_box(Vector3(0, h - 0.25, z), Vector3(w, 0.5, 0.4), _steel_mat, false)
		z += beam_spacing


func _grid(columns: int, rows: int, spacing: Vector2) -> Array[Vector2]:
	var points: Array[Vector2] = []
	for c in columns:
		for r in rows:
			points.append(Vector2((c - (columns - 1) / 2.0) * spacing.x, (r - (rows - 1) / 2.0) * spacing.y))
	return points


func _build_pillars() -> void:
	var h: float = room_size.y
	for p in _grid(pillar_columns, pillar_rows, pillar_spacing):
		_box(Vector3(p.x, h / 2, p.y), Vector3(pillar_size, h, pillar_size), _pillar_mat)
		var band: float = pillar_size + 0.04
		_box(Vector3(p.x, pillar_band_y, p.y), Vector3(band, pillar_band_height, band), _stripe_mat, false, false)


func _build_lights() -> void:
	var h: float = room_size.y
	for p in _grid(light_columns, light_rows, light_spacing):
		var lamp := Node3D.new()
		lamp.position = Vector3(p.x, h - lamp_drop, p.y)
		add_child(lamp)

		var shade := MeshInstance3D.new()
		var cone := CylinderMesh.new()
		cone.top_radius = 0.15
		cone.bottom_radius = 0.6
		cone.height = 0.4
		cone.radial_segments = 8
		cone.rings = 1
		shade.mesh = cone
		shade.material_override = _steel_mat
		lamp.add_child(shade)

		var bulb := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.2
		sphere.height = 0.4
		sphere.radial_segments = 8
		sphere.rings = 4
		bulb.mesh = sphere
		bulb.material_override = _bulb_mat
		bulb.position.y = -0.25
		bulb.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		lamp.add_child(bulb)

		var rod := _box(Vector3(p.x, h - lamp_drop / 2 + 0.2, p.y), Vector3(0.05, lamp_drop - 0.4, 0.05), _steel_mat, false, false)
		rod.name = "Rod"

		var spot := SpotLight3D.new()
		spot.position.y = -0.3
		spot.rotation_degrees.x = -90.0
		spot.light_color = light_color
		spot.light_energy = light_energy
		spot.spot_range = light_range
		spot.spot_angle = light_angle_deg
		spot.shadow_enabled = true
		lamp.add_child(spot)


func _build_markings() -> void:
	var w: float = room_size.x
	var l: float = room_size.z
	var y: float = 0.01
	var thin: Vector3 = Vector3(stripe_width, 0.02, l - 2 * stripe_inset)
	# Solid border strips.
	var bx: float = w / 2 - stripe_inset
	var bz: float = l / 2 - stripe_inset
	_box(Vector3(-bx, y, 0), thin, _stripe_mat, false, false)
	_box(Vector3(bx, y, 0), thin, _stripe_mat, false, false)
	_box(Vector3(0, y, -bz), Vector3(w - 2 * stripe_inset, 0.02, stripe_width), _stripe_mat, false, false)
	_box(Vector3(0, y, bz), Vector3(w - 2 * stripe_inset, 0.02, stripe_width), _stripe_mat, false, false)
	# Dashed lane lines.
	var z: float = -bz + dash_length / 2
	while z + dash_length / 2 <= bz:
		for x in [-lane_x, lane_x]:
			_box(Vector3(x, y, z), Vector3(stripe_width, 0.02, dash_length), _stripe_mat, false, false)
		z += dash_length + dash_gap
