class_name FlyingScrewPool
extends Node3D
## Fixed-size pool of lightweight "flying" screws (no nodes, no physics bodies) drawn by two MultiMeshes.
## Lifecycle: spawn() -> PULLED (accelerates to the anchor) -> CLUMPED (sticks in a blob) -> COLLECTING (flies to the hand) -> FREE.
## All state is in preallocated arrays; nothing is allocated per frame.
## Keep this node top_level and at the origin: everything is in world space.

enum State { FREE, PULLED, CLUMPED, COLLECTING }

const SHADER: Shader = preload("res://assets/materials/screw.gdshader")
const HIDDEN: Transform3D = Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

@export var capacity: int = 128 ## must exceed the magnet's max held, with room for a batch still collecting
@export var bounds_extent: float = 100.0

@export_group("Pull")
@export var pull_acceleration: float = 45.0
@export var acceleration_ramp: float = 3.0 ## accel multiplier grows by this per second in flight
@export var max_speed: float = 16.0
@export var damping: float = 1.2
@export var jitter: float = 30.0
@export var swirl: float = 14.0 ## sideways acceleration, makes paths curve
@export var launch_speed: float = 2.5 ## initial hop out of the pile
@export var spin_speed: float = 14.0
@export var arrival_distance: float = 0.1
@export var max_pull_time: float = 2.0 ## failsafe: force-clump after this long

@export_group("Clump")
@export var clump_radius_min: float = 0.06
@export var clump_radius_max: float = 0.24 ## blob radius when the magnet is full
@export var clump_stiffness: float = 20.0
@export var clump_wobble: float = 0.012
@export var clump_spin_factor: float = 0.2

@export_group("Collect")
@export var collect_time: float = 0.22
@export var collect_stagger: float = 0.12

var _state := PackedByteArray()
var _type := PackedByteArray()
var _pos := PackedVector3Array()
var _vel := PackedVector3Array()
var _start := PackedVector3Array()
var _offset := PackedVector3Array() ## clump position as a fraction of blob radius, in anchor space
var _axis := PackedVector3Array()
var _spin := PackedFloat32Array()
var _age := PackedFloat32Array()
var _scale := PackedFloat32Array()
var _basis: Array[Basis] = []
var _free := PackedInt32Array() ## stack of free slot ids
var _free_top: int = 0
var _held: int = 0 ## PULLED + CLUMPED
var _live: int = 0 ## everything not FREE
var _multimeshes: Array[MultiMesh] = []
var _time: float = 0.0

var _anchor_pos: Vector3
var _anchor_basis: Basis = Basis.IDENTITY
var _fill: float = 0.0
var _collect_pos: Vector3


func _ready() -> void:
	_state.resize(capacity)
	_type.resize(capacity)
	_pos.resize(capacity)
	_vel.resize(capacity)
	_start.resize(capacity)
	_offset.resize(capacity)
	_axis.resize(capacity)
	_spin.resize(capacity)
	_age.resize(capacity)
	_scale.resize(capacity)
	_basis.resize(capacity)
	_free.resize(capacity)
	for i in capacity:
		_free[i] = capacity - 1 - i # slot 0 is popped first
	_free_top = capacity

	var material := ShaderMaterial.new()
	material.shader = SHADER
	var meshes: Array[ArrayMesh] = [ScrewMeshFactory.make_screw(), ScrewMeshFactory.make_bolt()]
	for type in meshes.size():
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true
		mm.mesh = meshes[type]
		mm.instance_count = capacity
		for i in capacity:
			mm.set_instance_transform(i, HIDDEN)
		_multimeshes.append(mm)
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3.ONE * -bounds_extent, Vector3.ONE * bounds_extent * 2.0) # instances move every frame
		add_child(node)


func get_held_count() -> int:
	return _held


func has_free() -> bool:
	return _free_top > 0


## Where the magnet tip is, which way its blob is oriented, how full it is (0..1), and where collected screws fly to.
func set_anchor(pos: Vector3, basis: Basis, fill: float, collect_pos: Vector3) -> void:
	_anchor_pos = pos
	_anchor_basis = basis
	_fill = fill
	_collect_pos = collect_pos


## Takes over a screw that was just hidden in a pile. Returns false if the pool is full.
func spawn(type: int, xform: Transform3D, color: Color) -> bool:
	if _free_top == 0:
		return false
	_free_top -= 1
	var i: int = _free[_free_top]
	_state[i] = State.PULLED
	_type[i] = type
	_pos[i] = xform.origin
	_basis[i] = xform.basis.orthonormalized()
	_scale[i] = xform.basis.get_scale().x
	_vel[i] = (Vector3.UP * randf_range(0.5, 1.0) + Vector3(randf_range(-1.0, 1.0), 0.0, randf_range(-1.0, 1.0)) * 0.5) * launch_speed
	_axis[i] = (Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) + Vector3.UP * 0.01).normalized()
	_spin[i] = spin_speed * randf_range(0.6, 1.4) * (1.0 if randf() < 0.5 else -1.0)
	_offset[i] = Vector3(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).limit_length(1.0)
	_age[i] = 0.0
	_multimeshes[type].set_instance_color(i, color)
	_held += 1
	_live += 1
	return true


## Sends everything held to the hand. Returns the summed value (values is indexed by screw type).
func collect_all(values: Array[int]) -> int:
	var total: int = 0
	for i in capacity:
		var s: int = _state[i]
		if s == State.PULLED or s == State.CLUMPED:
			total += values[_type[i]]
			_state[i] = State.COLLECTING
			_age[i] = -0.0001 - randf() * collect_stagger # negative = still waiting in the blob
	_held = 0
	return total


func _process(delta: float) -> void:
	if _live == 0:
		return
	_time += delta
	var damp: float = exp(-damping * delta)
	var stiff: float = 1.0 - exp(-clump_stiffness * delta)
	var radius: float = lerpf(clump_radius_min, clump_radius_max, _fill)

	for i in capacity:
		var s: int = _state[i]
		if s == State.FREE:
			continue
		var scale_now: float = _scale[i]
		var spin: float = _spin[i]

		if s == State.PULLED:
			_age[i] += delta
			var to: Vector3 = _anchor_pos - _pos[i]
			var dist: float = to.length()
			# Fast screws can skip past the tip in one frame, so count a swept arrival.
			if dist < arrival_distance + _vel[i].length() * delta or _age[i] > max_pull_time:
				_state[i] = State.CLUMPED
			else:
				var dir: Vector3 = to / dist
				var accel: Vector3 = dir * pull_acceleration * (1.0 + acceleration_ramp * _age[i])
				accel += dir.cross(Vector3.UP) * swirl
				accel += Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * jitter
				_vel[i] = ((_vel[i] + accel * delta) * damp).limit_length(max_speed)
				_pos[i] += _vel[i] * delta
		else:
			var collecting_flight: bool = false
			if s == State.COLLECTING:
				var before: float = _age[i]
				_age[i] += delta
				if _age[i] >= 0.0:
					if before < 0.0:
						_start[i] = _pos[i]
					var k: float = minf(_age[i] / collect_time, 1.0)
					var e: float = k * k # ease-in, accelerates into the hand
					_pos[i] = _start[i].lerp(_collect_pos, e)
					scale_now *= 1.0 - e
					collecting_flight = true
					if k >= 1.0:
						_free_slot(i)
						continue
			if not collecting_flight:
				var target: Vector3 = _anchor_pos + _anchor_basis * (_offset[i] * radius)
				target += Vector3(sin(_time * 17.0 + i * 1.7), cos(_time * 13.0 + i * 2.3), sin(_time * 11.0 + i)) * clump_wobble
				_pos[i] = _pos[i].lerp(target, stiff)
				spin *= clump_spin_factor

		_basis[i] = (Basis(_axis[i], spin * delta) * _basis[i]).orthonormalized()
		_multimeshes[_type[i]].set_instance_transform(i, Transform3D(_basis[i] * scale_now, _pos[i]))


func _free_slot(i: int) -> void:
	_state[i] = State.FREE
	_multimeshes[_type[i]].set_instance_transform(i, HIDDEN)
	_free[_free_top] = i
	_free_top += 1
	_live -= 1
