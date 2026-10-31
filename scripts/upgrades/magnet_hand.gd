class_name MagnetHand
extends Node3D
## The held magnet (child of the camera). Unlocked by buying it in the shop.
## Hold the magnet button: screws in a cone ahead are pulled out of the piles into the flying pool.
## Release: everything clumped on the tip is cashed in as one payout.

@export var item_id: StringName = &"small_magnet"
@export var start_owned: bool = false ## debug: skip the shop

@export_group("Pull")
@export var max_held: int = 50
@export var pull_range: float = 3.5
@export_range(1.0, 89.0) var cone_half_angle_deg: float = 30.0
@export var pull_rate: float = 70.0 ## screws per second
@export var pull_interval: float = 0.04 ## seconds between cone queries
@export var burst_cap: float = 6.0 ## max screws grabbed in one query
@export var screw_values: Array[int] = [1, 1] ## base value per ScrewPile.ScrewType

@export_group("Payout")
@export var popup_distance: float = 1.8
@export var popup_height: float = 0.3
@export var collect_offset: Vector3 = Vector3(0.0, -0.2, -0.2) ## camera space

@export_group("Hand")
@export var hand_offset: Vector3 = Vector3(0.28, -0.26, -0.6)
@export var active_offset: Vector3 = Vector3(0.0, 0.03, -0.1) ## lunges forward while pulling
@export var hand_rotation_deg: Vector3 = Vector3(-75.0, 10.0, 0.0)
@export var visual_scale: float = 1.6
@export var tip_local: Vector3 = Vector3(0.0, 0.15, 0.0) ## clump center, in magnet mesh space
@export var hand_smoothing: float = 12.0
@export var shake_amount: float = 0.012
@export var glow_base: float = 1.5
@export var glow_per_fill: float = 2.5

var _owned: bool = false
var _was_active: bool = false
var _budget: float = 0.0
var _tick: float = 0.0
var _last_held: int = -1
var _piles: Array[ScrewPile] = []
var _cand := PackedInt32Array()
var _hand_pos: Vector3

var _visual: Node3D
var _mesh: MeshInstance3D
var _tip: Node3D
var _tip_mat: StandardMaterial3D

@onready var _camera: Camera3D = get_parent()
@onready var _pool: FlyingScrewPool = $FlyingScrewPool


func _ready() -> void:
	_build_visual()
	EventBus.item_purchased.connect(_on_item_purchased)
	if start_owned:
		_equip(false)


func _build_visual() -> void:
	_hand_pos = hand_offset
	_visual = Node3D.new()
	_visual.position = hand_offset
	_visual.visible = false
	add_child(_visual)

	var mesh: ArrayMesh = MagnetMeshFactory.make()
	_tip_mat = mesh.surface_get_material(1) as StandardMaterial3D
	_mesh = MeshInstance3D.new()
	_mesh.mesh = mesh
	_mesh.rotation_degrees = hand_rotation_deg
	_mesh.scale = Vector3.ONE * visual_scale
	_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_visual.add_child(_mesh)

	_tip = Node3D.new()
	_tip.position = tip_local
	_mesh.add_child(_tip)


func _on_item_purchased(purchased_id: StringName) -> void:
	if purchased_id == item_id:
		_equip(true)


func _equip(with_pop: bool) -> void:
	_owned = true
	_visual.visible = true
	if with_pop:
		_visual.scale = Vector3.ZERO
		create_tween().tween_property(_visual, "scale", Vector3.ONE, 0.35).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _process(delta: float) -> void:
	if not _owned:
		return
	var active: bool = Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_action_pressed("magnet")
	if active:
		if not _was_active:
			_refresh_piles()
		_pull(delta)
	elif _was_active:
		_release()
	_was_active = active

	var held: int = _pool.get_held_count()
	var fill: float = float(held) / float(max_held)
	if held != _last_held:
		_last_held = held
		EventBus.magnet_held_changed.emit(held, max_held)
	_update_visual(delta, active, fill)
	var cam_basis: Basis = _camera.global_basis
	_pool.set_anchor(_tip.global_position, cam_basis, fill, _camera.global_position + cam_basis * collect_offset)


func _refresh_piles() -> void:
	_piles.clear()
	for node in get_tree().get_nodes_in_group("screw_pile"):
		_piles.append(node as ScrewPile)


func _pull(delta: float) -> void:
	_budget = minf(_budget + pull_rate * delta, burst_cap)
	_tick -= delta
	if _tick > 0.0:
		return
	_tick = pull_interval

	var want: int = mini(int(_budget), max_held - _pool.get_held_count())
	if want <= 0:
		if _pool.get_held_count() >= max_held:
			_budget = 0.0
		return

	var origin: Vector3 = _camera.global_position
	var forward: Vector3 = -_camera.global_basis.z
	var cos_half: float = cos(deg_to_rad(cone_half_angle_deg))
	var center: Vector3 = origin + forward * pull_range * 0.5
	var query_radius: float = pull_range * 0.75 # covers the whole cone from its center
	for pile in _piles:
		if want <= 0:
			break
		if pile.global_position.distance_to(center) > pile.pile_radius + query_radius:
			continue
		var n: int = pile.screws_in_radius_into(center, query_radius, _cand)
		var kept: int = 0
		for k in n: # keep only screws inside the cone, in place
			var id: int = _cand[k]
			var d: Vector3 = pile.get_screw_world_position(id) - origin
			var dist: float = d.length()
			if dist <= pull_range and d.dot(forward) >= cos_half * dist:
				_cand[kept] = id
				kept += 1
		while want > 0 and kept > 0 and _pool.has_free():
			var pick: int = randi() % kept
			var id: int = _cand[pick]
			_cand[pick] = _cand[kept - 1]
			kept -= 1
			if _take(pile, id):
				want -= 1
				_budget -= 1.0


func _take(pile: ScrewPile, id: int) -> bool:
	var xform: Transform3D = pile.get_screw_world_transform(id)
	var type: int = pile.get_screw_type(id)
	var color: Color = pile.get_screw_color(id)
	if not pile.claim_screw(id):
		return false
	pile.hide_screw(id)
	return _pool.spawn(type, xform, color)


func _release() -> void:
	_budget = 0.0
	var count: int = _pool.get_held_count()
	if count == 0:
		return
	var total: int = _pool.collect_all(screw_values)
	var popup: Vector3 = _camera.global_position - _camera.global_basis.z * popup_distance + Vector3.UP * popup_height
	Economy.add_money(total, popup)
	EventBus.magnet_released.emit(count, popup)


func _update_visual(delta: float, active: bool, fill: float) -> void:
	var target: Vector3 = hand_offset + (active_offset if active else Vector3.ZERO)
	_hand_pos = _hand_pos.lerp(target, 1.0 - exp(-hand_smoothing * delta))
	var shake := Vector3.ZERO
	if active:
		shake = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * shake_amount * (0.4 + fill)
	_visual.position = _hand_pos + shake
	var glow: float = glow_base + glow_per_fill * fill if active else 0.0
	_tip_mat.emission_energy_multiplier = lerpf(_tip_mat.emission_energy_multiplier, glow, 1.0 - exp(-10.0 * delta))
