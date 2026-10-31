class_name HandCollector
extends Node
## Child of the camera. Click (or hold) to grab the screw nearest to where the crosshair ray hits a pile.
## The grabbed screw flies to the hand inside its own MultiMesh, shrinking, then is hidden.

class Flight:
	var pile: ScrewPile
	var index: int
	var start: Transform3D
	var t: float = 0.0

@export var reach: float = 4.0
@export var pickup_radius: float = 0.6
@export var pickup_cooldown: float = 0.1 ## also the rate while holding the button
@export var ray_collision_mask: int = 1
@export var screw_values: Array[int] = [1, 1] ## base value per ScrewPile.ScrewType

@export_group("Flight")
@export var flight_time: float = 0.25
@export var flight_target_offset: Vector3 = Vector3(0.15, -0.2, -0.35) ## camera space
@export var flight_arc: float = 0.15
@export var flight_spin: float = 6.0 ## radians over the flight

var _flights: Array[Flight] = []
var _cooldown: float = 0.0

@onready var _camera: Camera3D = get_parent()


func _physics_process(delta: float) -> void:
	_cooldown -= delta
	if _cooldown <= 0.0 and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("pickup"):
		if _try_pickup():
			_cooldown = pickup_cooldown


func _process(delta: float) -> void:
	for i in range(_flights.size() - 1, -1, -1):
		var flight: Flight = _flights[i]
		if not is_instance_valid(flight.pile):
			_flights.remove_at(i)
			continue
		flight.t += delta / flight_time
		var k: float = minf(flight.t, 1.0)
		var e: float = k * k # ease-in: accelerates into the hand
		var target: Vector3 = _camera.global_transform * flight_target_offset
		var origin: Vector3 = flight.start.origin.lerp(target, e) + Vector3.UP * sin(k * PI) * flight_arc
		var basis: Basis = (Basis(Vector3.UP, e * flight_spin) * flight.start.basis).scaled(Vector3.ONE * (1.0 - e))
		flight.pile.set_screw_world_transform(flight.index, Transform3D(basis, origin))
		if flight.t >= 1.0:
			flight.pile.hide_screw(flight.index)
			_flights.remove_at(i)


func _try_pickup() -> bool:
	var from: Vector3 = _camera.global_position
	var to: Vector3 = from - _camera.global_basis.z * reach
	var query := PhysicsRayQueryParameters3D.create(from, to, ray_collision_mask)
	var hit: Dictionary = _camera.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		return false
	var pile := (hit["collider"] as Node).get_parent() as ScrewPile
	if pile == null:
		return false
	var index: int = pile.find_nearest(hit["position"], pickup_radius)
	if index < 0 or not pile.claim_screw(index):
		return false

	var flight := Flight.new()
	flight.pile = pile
	flight.index = index
	flight.start = pile.get_screw_world_transform(index)
	_flights.append(flight)
	EventBus.screw_picked.emit(screw_values[pile.get_screw_type(index)], flight.start.origin)
	return true
