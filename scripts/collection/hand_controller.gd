class_name HandController
extends Node
## Child of the camera. Hover highlights the object under the crosshair; click picks it up for inspection
## (mouse rotates it); E submits it; right click tosses it. Toss without holding = quick dig.
## Tossed objects fly to a spot in the ring around the pile and stay there, so nothing leaks which one is the target.

enum State { IDLE, PICKING, INSPECT, FOUND }

class Flight:
	var node: MeshInstance3D
	var pile: ObjectPile
	var j: int
	var from_center: Vector3
	var from_q: Quaternion
	var landing: Transform3D ## pile-local: orientation and OBB center
	var spin_axis: Vector3
	var scale: float
	var axial: float
	var t: float = 0.0

@export var reach: float = 3.0

@export_group("Inspect")
@export var inspect_fov: float = 45.0
@export var inspect_pitch: float = 0.6 ## radians the head tilts toward you at the start
@export var inspect_sensitivity: float = 0.008
@export var inspect_fit_margin: float = 2.1
@export var inspect_min_distance: float = 0.55
@export var inspect_max_distance: float = 1.6
@export var pick_time: float = 0.2
@export var pick_arc: float = 0.1

@export_group("Tools (Hard/Expert)")
@export var tools_pitch: float = 0.2 ## head tilt toward you when tools are shown (keeps the axis near vertical)
@export var tools_object_x: float = -0.3 ## object sits left of the ruler
@export var tools_fit_margin: float = 1.75

@export_group("Toss")
@export var toss_time: float = 0.5
@export var toss_arc: float = 0.7
@export var toss_spin: float = 9.0
@export var toss_pool_size: int = 8

@export_group("Look")
@export var hover_highlight: float = 0.85
@export var inspect_light_energy: float = 1.6 ## soft light on the held object
@export var inspect_light_color: Color = Color(1.0, 0.95, 0.85)
@export var inspect_light_offset: Vector3 = Vector3(0.3, 0.4, 0.3)

var _state: State = State.IDLE
var _piles: Array[ObjectPile] = []
var _rng := RandomNumberGenerator.new()

var _obj: MeshInstance3D ## the one promoted node: hovered or held object
var _obj_material: ShaderMaterial
var _hover_pile: ObjectPile
var _hover_j: int = -1

var _held_pile: ObjectPile
var _held_j: int = -1
var _held_scale: float = 1.0
var _held_axial: float = 0.0
var _inspect_basis: Basis = Basis.IDENTITY
var _inspect_dist: float = 0.8
var _awaiting_result: bool = false
var _pick_t: float = 0.0
var _pick_from_center: Vector3
var _pick_from_q: Quaternion

var _tools: InspectTools
var _tools_on: bool = false
var _inspect_shift: Vector3 = Vector3.ZERO
var _inspect_light: OmniLight3D
var _flight_pool: Array[MeshInstance3D] = []
var _flights: Array[Flight] = []

@onready var _camera: Camera3D = get_parent()


func _ready() -> void:
	_rng.randomize()
	_obj = _make_node()
	_obj_material = _obj.material_override as ShaderMaterial
	for i in toss_pool_size:
		_flight_pool.append(_make_node())
	_inspect_light = OmniLight3D.new()
	_inspect_light.light_color = inspect_light_color
	_inspect_light.omni_range = 3.0
	_inspect_light.light_energy = 0.0
	_inspect_light.position = inspect_light_offset
	_camera.add_child.call_deferred(_inspect_light)
	_tools = InspectTools.new()
	_tools.visible = false
	_camera.add_child.call_deferred(_tools)
	EventBus.round_started.connect(_on_round_started)
	EventBus.submission_result.connect(_on_submission_result)
	EventBus.inspect_changed.connect(func(active: bool, _fov: float) -> void:
		create_tween().tween_property(_inspect_light, "light_energy", inspect_light_energy if active else 0.0, 0.2))


func _make_node() -> MeshInstance3D:
	var node := MeshInstance3D.new()
	node.top_level = true
	node.visible = false
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var material := ShaderMaterial.new() # one per node: each carries its own object's color and shaft data
	material.shader = ObjectPile.SHADER
	material.set_shader_parameter("body_len", ObjDefs.BODY_LEN)
	material.set_shader_parameter("use_override", true)
	node.material_override = material
	add_child(node)
	return node


func _on_round_started(data: RoundData) -> void:
	_tools_on = data.config.inspect_tools
	_tools.visible = false
	if _tools_on:
		_tools.build(data.config.units_per_mm, ObjDefs.PITCHES)
	_clear_hover(false)
	_obj.visible = false
	for flight in _flights:
		flight.node.visible = false
		_flight_pool.append(flight.node)
	_flights.clear()
	_held_pile = null
	_state = State.IDLE
	_awaiting_result = false
	EventBus.inspect_changed.emit(false, 0.0)
	_piles.clear()
	for node in get_tree().get_nodes_in_group("object_pile"):
		if not node.is_queued_for_deletion():
			_piles.append(node as ObjectPile)


func _unhandled_input(event: InputEvent) -> void:
	if (_state == State.INSPECT or _state == State.FOUND) and event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var motion: InputEventMouseMotion = event
		_inspect_basis = (Basis(Vector3.UP, motion.relative.x * inspect_sensitivity) * Basis(Vector3.RIGHT, motion.relative.y * inspect_sensitivity) * _inspect_basis).orthonormalized()


func _process(delta: float) -> void:
	_update_flights(delta)
	var active: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED
	match _state:
		State.IDLE:
			_update_hover(active)
			if active and _hover_j >= 0:
				if Input.is_action_just_pressed("pickup"):
					_pick()
				elif Input.is_action_just_pressed("toss"):
					_quick_toss()
		State.PICKING:
			_pick_t = minf(_pick_t + delta / maxf(pick_time, 0.01), 1.0)
			var e: float = _pick_t * _pick_t * (3.0 - 2.0 * _pick_t)
			var target: Transform3D = _held_pose()
			var center: Vector3 = _pick_from_center.lerp(_held_center(), e) + Vector3.UP * sin(e * PI) * pick_arc
			var q: Quaternion = _pick_from_q.slerp(_held_rotation().get_rotation_quaternion(), e)
			_obj.global_transform = _pose(Basis(q), center)
			if _pick_t >= 1.0:
				_obj.global_transform = target
				_state = State.INSPECT
		State.INSPECT:
			_obj.global_transform = _held_pose()
			if active and not _awaiting_result:
				if Input.is_action_just_pressed("submit"):
					_awaiting_result = true
					EventBus.object_submitted.emit(_held_pile.layout.ids[_held_j])
				elif Input.is_action_just_pressed("toss"):
					_toss_held()
		State.FOUND:
			_obj.global_transform = _held_pose()


# --- hover ---

func _update_hover(active: bool) -> void:
	var best_pile: ObjectPile = null
	var best_j: int = -1
	if active:
		var origin: Vector3 = _camera.global_position
		var direction: Vector3 = -_camera.global_basis.z
		var best_d: float = reach
		for pile in _piles:
			var j: int = pile.pick_ray(origin, direction, best_d)
			if j >= 0:
				best_pile = pile
				best_j = j
				best_d = pile.last_hit_distance
	if best_pile != _hover_pile or best_j != _hover_j:
		_clear_hover(true)
		if best_j >= 0:
			_set_hover(best_pile, best_j)
	elif _hover_j >= 0:
		_obj.global_transform = _hover_pile.world_transform(_hover_j) # follows a settle in progress


func _set_hover(pile: ObjectPile, j: int) -> void:
	_hover_pile = pile
	_hover_j = j
	_setup_node(_obj, pile, j)
	_obj_material.set_shader_parameter("highlight", hover_highlight)
	pile.hide_object(j)
	_obj.global_transform = pile.world_transform(j)
	_obj.visible = true


func _clear_hover(restore: bool) -> void:
	if _hover_j >= 0 and restore and is_instance_valid(_hover_pile):
		_hover_pile.show_object(_hover_j)
	_hover_pile = null
	_hover_j = -1
	if _state == State.IDLE:
		_obj.visible = false


func _setup_node(node: MeshInstance3D, pile: ObjectPile, j: int) -> void:
	var g: int = pile.layout.ids[j]
	var c: Array[PackedInt32Array] = pile.data.cols
	node.mesh = ObjectMeshFactory.get_mesh(c[ObjDefs.Prop.TYPE][g], c[ObjDefs.Prop.HEAD][g], c[ObjDefs.Prop.DRIVE][g])
	var material: ShaderMaterial = node.material_override
	var tint: Color = pile.object_color(j)
	var data: Color = pile.shader_data(g)
	# Vector4, not Color: Godot would sRGB-convert a Color assigned to a plain vec4 uniform.
	material.set_shader_parameter("override_color", Vector4(tint.r, tint.g, tint.b, tint.a))
	material.set_shader_parameter("override_data", Vector4(data.r, data.g, data.b, data.a))
	material.set_shader_parameter("highlight", 0.0)


# --- pick / inspect ---

func _pick() -> void:
	_held_pile = _hover_pile
	_held_j = _hover_j
	_held_scale = _held_pile.object_scale(_held_j)
	_held_axial = _held_pile.layout.axial_center[_held_j]
	var half: Vector3 = _held_pile.layout.half[_held_j]
	var diameter: float = 2.0 * sqrt(half.x * half.x + half.y * half.y)
	_inspect_dist = clampf(diameter / (2.0 * tan(deg_to_rad(inspect_fov) / 2.0)) * inspect_fit_margin, inspect_min_distance, inspect_max_distance)
	_inspect_shift = Vector3.ZERO
	var pitch: float = inspect_pitch
	if _tools_on:
		pitch = tools_pitch
		_inspect_shift = Vector3(tools_object_x, 0.0, 0.0)
		var needed: float = _tools.length_world * tools_fit_margin / (2.0 * tan(deg_to_rad(inspect_fov) / 2.0))
		_inspect_dist = clampf(maxf(_inspect_dist, needed), inspect_min_distance, 2.0)
		# Zero line = where the head plane sits when the axis is vertical; tools share the object's depth.
		_tools.position = Vector3(tools_object_x, -_held_axial * cos(pitch), -_inspect_dist)
		_tools.visible = true
	_inspect_basis = Basis(Vector3.RIGHT, pitch)
	_pick_from_center = _held_pile.object_world_center(_held_j)
	_pick_from_q = _held_pile.layout.rot[_held_j].get_rotation_quaternion()
	_pick_t = 0.0
	_hover_pile = null # the node now belongs to the held object
	_hover_j = -1
	_held_pile.remove_object(_held_j)
	_obj_material.set_shader_parameter("highlight", 0.0)
	_state = State.PICKING
	_awaiting_result = false
	EventBus.inspect_changed.emit(true, inspect_fov)


func _held_rotation() -> Basis:
	return _camera.global_basis * _inspect_basis


func _held_center() -> Vector3:
	return _camera.global_position + _camera.global_basis * (_inspect_shift + Vector3(0.0, 0.0, -_inspect_dist))


func _held_pose() -> Transform3D:
	return _pose(_held_rotation(), _held_center())


## Node transform for an object whose OBB center is at `center` with orientation `rotation`.
func _pose(rotation: Basis, center: Vector3) -> Transform3D:
	return Transform3D(rotation * _held_scale, center - rotation * Vector3(0.0, _held_axial, 0.0))


func _on_submission_result(correct: bool) -> void:
	_awaiting_result = false
	if _state != State.INSPECT:
		return
	if correct:
		_state = State.FOUND
	else:
		_toss_held()


# --- toss ---

func _toss_held() -> void:
	var center: Vector3 = _held_center()
	var q: Quaternion = _held_rotation().get_rotation_quaternion()
	_obj.visible = false
	_tools.visible = false
	_state = State.IDLE
	EventBus.inspect_changed.emit(false, 0.0)
	_launch(_held_pile, _held_j, center, q)
	_held_pile = null


func _quick_toss() -> void:
	var pile: ObjectPile = _hover_pile
	var j: int = _hover_j
	var center: Vector3 = pile.object_world_center(j)
	var q: Quaternion = pile.layout.rot[j].get_rotation_quaternion()
	_hover_pile = null
	_hover_j = -1
	_obj.visible = false
	pile.remove_object(j)
	_launch(pile, j, center, q)


func _launch(pile: ObjectPile, j: int, center: Vector3, q: Quaternion) -> void:
	if _flight_pool.is_empty(): # all flight nodes busy: land the oldest immediately
		_finish_flight(_flights[0])
		_flights.remove_at(0)
	var flight := Flight.new()
	flight.node = _flight_pool.pop_back()
	flight.pile = pile
	flight.j = j
	flight.from_center = center
	flight.from_q = q
	flight.landing = pile.plan_landing(j, _rng)
	flight.spin_axis = Vector3(_rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0), _rng.randf_range(-1.0, 1.0)).normalized()
	flight.scale = pile.object_scale(j)
	flight.axial = pile.layout.axial_center[j]
	_setup_node(flight.node, pile, j)
	flight.node.visible = true
	_flights.append(flight)
	_apply_flight(flight, 0.0)


func _update_flights(delta: float) -> void:
	for i in range(_flights.size() - 1, -1, -1):
		var flight: Flight = _flights[i]
		if not is_instance_valid(flight.pile):
			flight.node.visible = false
			_flight_pool.append(flight.node)
			_flights.remove_at(i)
			continue
		flight.t += delta / maxf(toss_time, 0.01)
		if flight.t >= 1.0:
			_finish_flight(flight)
			_flights.remove_at(i)
		else:
			_apply_flight(flight, flight.t)


func _apply_flight(flight: Flight, t: float) -> void:
	var land_center: Vector3 = flight.pile.global_transform * flight.landing.origin
	var center: Vector3 = flight.from_center.lerp(land_center, t) + Vector3.UP * sin(t * PI) * toss_arc
	var q: Quaternion = flight.from_q.slerp(flight.landing.basis.get_rotation_quaternion(), t)
	var rotation: Basis = Basis(flight.spin_axis, sin(t * PI) * toss_spin) * Basis(q)
	flight.node.global_transform = Transform3D(rotation * flight.scale, center - rotation * Vector3(0.0, flight.axial, 0.0))


func _finish_flight(flight: Flight) -> void:
	flight.node.visible = false
	_flight_pool.append(flight.node)
	if is_instance_valid(flight.pile):
		flight.pile.restore_object(flight.j, flight.landing)
