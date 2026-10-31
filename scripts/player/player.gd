class_name Player
extends CharacterBody3D
## First-person controller: mouse look, WASD, sprint, jump, subtle head bob.

@export_group("Movement")
@export var walk_speed: float = 5.0
@export var sprint_speed: float = 8.5
@export var jump_velocity: float = 4.8
@export var acceleration: float = 45.0
@export var deceleration: float = 55.0
@export_range(0.0, 1.0) var air_control: float = 0.35
@export var coyote_time: float = 0.1
@export var jump_buffer_time: float = 0.12

@export_group("Look")
@export var mouse_sensitivity: float = 0.0022
@export var max_pitch_deg: float = 89.0

@export_group("Head bob")
@export var head_bob_enabled: bool = true
@export var bob_amplitude: float = 0.035
@export var bob_radians_per_meter: float = 8.0
@export var bob_smoothing: float = 12.0

@export_group("Camera feel")
@export var sprint_fov_boost: float = 6.0
@export var fov_smoothing: float = 8.0
@export var landing_dip_scale: float = 0.012
@export var landing_dip_max: float = 0.12

@export_group("Stance")
@export var stand_head_height: float = 1.6
@export var crouch_head_height: float = 0.7
@export var crouch_capsule_height: float = 1.0
@export_range(0.1, 1.0) var crouch_speed_mult: float = 0.45
@export var lean_forward: float = 0.5 ## head moves this far ahead when leaning in
@export var lean_drop: float = 0.2
@export var stance_smoothing: float = 10.0

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _coyote: float = 0.0
var _jump_buffer: float = 0.0
var _bob_phase: float = 0.0
var _land_dip: float = 0.0
var _sprinting: bool = false
var _base_fov: float
var _fov: float
var _locked: bool = false ## true while inspecting: no movement or look
var _inspect_fov: float = 0.0
var _crouch: float = 0.0
var _lean: float = 0.0
var _capsule: CapsuleShape3D
var _capsule_height: float

@onready var _head: Node3D = $Head
@onready var _camera: Camera3D = $Head/Camera3D
@onready var _shape_node: CollisionShape3D = $CollisionShape3D


func _ready() -> void:
	_base_fov = _camera.fov
	_fov = _base_fov
	_capsule = _shape_node.shape as CapsuleShape3D
	_capsule_height = _capsule.height
	EventBus.inspect_changed.connect(_on_inspect_changed)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	elif event is InputEventMouseButton and event.is_pressed() and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event.is_action_pressed("toggle_head_bob"):
		head_bob_enabled = not head_bob_enabled
	elif event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and not _locked:
		var motion: InputEventMouseMotion = event
		rotate_y(-motion.relative.x * mouse_sensitivity)
		_head.rotation.x = clampf(_head.rotation.x - motion.relative.y * mouse_sensitivity,
				-deg_to_rad(max_pitch_deg), deg_to_rad(max_pitch_deg))


func _physics_process(delta: float) -> void:
	var was_on_floor: bool = is_on_floor()
	var fall_speed: float = -velocity.y

	if was_on_floor:
		_coyote = coyote_time
	else:
		_coyote -= delta
		velocity.y -= _gravity * delta

	_jump_buffer = jump_buffer_time if (Input.is_action_just_pressed("jump") and not _locked) else _jump_buffer - delta
	if _jump_buffer > 0.0 and _coyote > 0.0:
		velocity.y = jump_velocity
		_jump_buffer = 0.0
		_coyote = 0.0

	var input: Vector2 = Vector2.ZERO if _locked else Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction: Vector3 = (global_transform.basis * Vector3(input.x, 0.0, input.y)).normalized()
	_sprinting = Input.is_action_pressed("sprint") and input != Vector2.ZERO and _crouch < 0.5
	var target: Vector3 = direction * (sprint_speed if _sprinting else walk_speed) * lerpf(1.0, crouch_speed_mult, _crouch)
	var rate: float = acceleration if input != Vector2.ZERO else deceleration
	if not was_on_floor:
		rate *= air_control
	var horizontal: Vector3 = Vector3(velocity.x, 0.0, velocity.z).move_toward(target, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	move_and_slide()

	if is_on_floor() and not was_on_floor:
		_land_dip = minf(fall_speed * landing_dip_scale, landing_dip_max)


func _process(delta: float) -> void:
	var speed: float = Vector2(velocity.x, velocity.z).length()
	var walking: bool = is_on_floor() and speed > 0.5
	var amplitude: float = 0.0
	if head_bob_enabled and walking:
		_bob_phase += speed * bob_radians_per_meter * delta
		amplitude = bob_amplitude * clampf(speed / walk_speed, 0.0, 1.4)

	_land_dip = lerpf(_land_dip, 0.0, 1.0 - exp(-10.0 * delta))
	var bob := Vector3(cos(_bob_phase * 0.5) * amplitude * 0.5, sin(_bob_phase) * amplitude - _land_dip, 0.0)
	_camera.position = _camera.position.lerp(bob, 1.0 - exp(-bob_smoothing * delta))

	if not _locked: # stance is held while inspecting
		var k: float = 1.0 - exp(-stance_smoothing * delta)
		_crouch = lerpf(_crouch, 1.0 if Input.is_action_pressed("crouch") else 0.0, k)
		_lean = lerpf(_lean, 1.0 if Input.is_action_pressed("lean_in") else 0.0, k)
	_head.position = Vector3(0.0, lerpf(stand_head_height, crouch_head_height, _crouch) - lean_drop * _lean, -lean_forward * _lean)
	_capsule.height = lerpf(_capsule_height, crouch_capsule_height, _crouch)
	_shape_node.position.y = _capsule.height / 2.0

	var target_fov: float = _inspect_fov if _locked else _base_fov + (sprint_fov_boost if _sprinting and speed > walk_speed * 0.9 else 0.0)
	_fov = lerpf(_fov, target_fov, 1.0 - exp(-fov_smoothing * delta))
	_camera.fov = _fov



func _on_inspect_changed(active: bool, fov: float) -> void:
	_locked = active
	_inspect_fov = fov
