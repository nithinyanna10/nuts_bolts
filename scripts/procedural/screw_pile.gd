class_name ScrewPile
extends Node3D
## A mound of screws and bolts drawn with one MultiMeshInstance3D per mesh type.
## Per-screw data lives in parallel arrays; removal hides the instance (zero scale).
## Keep this node's scale at 1 (spatial queries assume it).

enum ScrewType { SCREW, BOLT }

const SHADER: Shader = preload("res://assets/materials/screw.gdshader")
const HIDDEN: Transform3D = Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

@export_group("Spawn")
@export var screw_count: int = 5000
@export_range(0.0, 1.0) var bolt_ratio: float = 0.2
@export var rng_seed: int = 0 ## 0 = random each run

@export_group("Mound")
@export var pile_radius: float = 2.2
@export var pile_height: float = 1.1
@export var center_bias: float = 0.8 ## radius = R * rand^bias. 0.5 = uniform over area, higher = denser center
@export_range(0.0, 1.0) var depth_min: float = 0.55 ## lowest layer as a fraction of mound height
@export var floor_offset: float = 0.04
@export var surface_jitter: float = 0.06

@export_group("Look")
@export var scale_variation: float = 0.25
@export var tint_clean: Color = Color(0.62, 0.64, 0.68)
@export var tint_rust: Color = Color(0.5, 0.24, 0.1)
@export var rust_bias: float = 0.8 ## rust = rand^bias. Below 1 = mostly rusty
@export_range(0.0, 1.0) var metallic: float = 0.6
@export_range(0.0, 1.0) var roughness_min: float = 0.3
@export_range(0.0, 1.0) var roughness_max: float = 0.8
@export var cast_shadows: bool = false

@export_group("Query")
@export var grid_cell_size: float = 0.5
@export var collider_margin: float = 0.08
@export var collider_segments: int = 12

var _positions := PackedVector3Array() ## pile-local
var _types := PackedByteArray()
var _active := PackedByteArray()
var _slots := PackedInt32Array() ## index inside the screw's type MultiMesh
var _multimeshes: Array[MultiMesh] = []
var _grid := SpatialGrid.new()
var _active_count: int = 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	if rng_seed != 0:
		rng.seed = rng_seed
	else:
		rng.randomize()

	_positions.resize(screw_count)
	_types.resize(screw_count)
	_active.resize(screw_count)
	_slots.resize(screw_count)

	var counts: Array[int] = []
	counts.resize(ScrewType.size())
	counts.fill(0)
	for i in screw_count:
		var type: int = ScrewType.BOLT if rng.randf() < bolt_ratio else ScrewType.SCREW
		_types[i] = type
		_slots[i] = counts[type]
		counts[type] += 1

	var meshes: Array[ArrayMesh] = [ScrewMeshFactory.make_screw(), ScrewMeshFactory.make_bolt()]
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("metallic", metallic)
	material.set_shader_parameter("roughness_min", roughness_min)
	material.set_shader_parameter("roughness_max", roughness_max)
	for type in ScrewType.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true # must be set before instance_count
		mm.mesh = meshes[type]
		mm.instance_count = counts[type]
		_multimeshes.append(mm)
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)

	for i in screw_count:
		var pos: Vector3 = _random_mound_position(rng)
		var rotation := Basis.from_euler(Vector3(rng.randf(), rng.randf(), rng.randf()) * TAU)
		var s: float = 1.0 + rng.randf_range(-scale_variation, scale_variation)
		var color: Color = tint_clean.lerp(tint_rust, pow(rng.randf(), rust_bias))
		color.a = rng.randf() # roughness variation, read by the shader
		var mm: MultiMesh = _multimeshes[_types[i]]
		mm.set_instance_transform(_slots[i], Transform3D(rotation.scaled(Vector3.ONE * s), pos))
		mm.set_instance_color(_slots[i], color)
		_positions[i] = pos
		_active[i] = 1
	_active_count = screw_count

	_grid.setup(grid_cell_size, _positions)
	_build_collider()


func _random_mound_position(rng: RandomNumberGenerator) -> Vector3:
	var f: float = pow(rng.randf(), center_bias)
	var angle: float = rng.randf() * TAU
	var surface: float = pile_height * (1.0 - f * f)
	var y: float = floor_offset + surface * lerpf(depth_min, 1.0, rng.randf()) + rng.randf() * surface_jitter
	return Vector3(cos(angle) * f * pile_radius, y, sin(angle) * f * pile_radius)


## One convex hull over the mound so the crosshair ray has something to hit (no per-screw colliders).
func _build_collider() -> void:
	var points := PackedVector3Array()
	for f: float in [1.0, 0.75, 0.5, 0.25]:
		var y: float = pile_height * (1.0 - f * f) + collider_margin
		for k in collider_segments:
			var a: float = TAU * k / collider_segments
			points.append(Vector3(cos(a) * f * pile_radius, y, sin(a) * f * pile_radius))
	points.append(Vector3(0.0, pile_height + collider_margin, 0.0))
	var shape := ConvexPolygonShape3D.new()
	shape.points = points
	var shape_node := CollisionShape3D.new()
	shape_node.shape = shape
	var body := StaticBody3D.new()
	body.add_child(shape_node)
	add_child(body)


func get_active_count() -> int:
	return _active_count


func is_active(index: int) -> bool:
	return _active[index] == 1


func get_screw_type(index: int) -> int:
	return _types[index]


func get_screw_world_transform(index: int) -> Transform3D:
	return global_transform * _multimeshes[_types[index]].get_instance_transform(_slots[index])


func set_screw_world_transform(index: int, xform: Transform3D) -> void:
	_multimeshes[_types[index]].set_instance_transform(_slots[index], global_transform.affine_inverse() * xform)


## Closest active screw to a world point within radius, or -1.
func find_nearest(world_point: Vector3, radius: float) -> int:
	return _grid.nearest(to_local(world_point), radius)


func screws_in_radius(world_point: Vector3, radius: float) -> PackedInt32Array:
	return _grid.query(to_local(world_point), radius)


## Logical removal: the screw can no longer be queried. It stays visible until hide_screw().
func claim_screw(index: int) -> bool:
	if _active[index] == 0:
		return false
	_active[index] = 0
	_active_count -= 1
	_grid.remove(index)
	return true


func hide_screw(index: int) -> void:
	_multimeshes[_types[index]].set_instance_transform(_slots[index], HIDDEN)


func remove_screw(index: int) -> void:
	if claim_screw(index):
		hide_screw(index)
