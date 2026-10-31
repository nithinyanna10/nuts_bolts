class_name ShopTerminal
extends Node3D
## A low-poly terminal. Stand within interact_radius and press the open_shop key to request the shop.

@export var interact_radius: float = 3.0
@export var label_text: String = "SHOP"
@export var screen_color: Color = Color(0.25, 1.0, 0.55)
@export var screen_energy: float = 2.0

var _near: bool = false


func _ready() -> void:
	_build_visual()
	_build_trigger()


func _build_visual() -> void:
	var steel := StandardMaterial3D.new()
	steel.albedo_color = Color(0.16, 0.17, 0.2)
	steel.metallic = 0.5
	steel.roughness = 0.5
	var screen := StandardMaterial3D.new()
	screen.albedo_color = screen_color
	screen.emission_enabled = true
	screen.emission = screen_color
	screen.emission_energy_multiplier = screen_energy

	var base_size := Vector3(0.9, 1.1, 0.6)
	_add_box(base_size, Vector3(0.0, base_size.y / 2.0, 0.0), Vector3.ZERO, steel, true)
	_add_box(Vector3(0.7, 0.45, 0.05), Vector3(0.0, 1.05, 0.31), Vector3(-15.0, 0.0, 0.0), screen, false)
	_add_box(Vector3(1.0, 0.1, 0.7), Vector3(0.0, 1.15, 0.0), Vector3.ZERO, steel, false)

	var sign := Label3D.new()
	sign.text = label_text
	sign.font_size = 96
	sign.pixel_size = 0.004
	sign.outline_size = 16
	sign.modulate = screen_color
	sign.shaded = false
	sign.position = Vector3(0.0, 1.75, 0.0)
	sign.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	add_child(sign)

	var glow := OmniLight3D.new()
	glow.light_color = screen_color
	glow.light_energy = 1.0
	glow.omni_range = 5.0
	glow.position = Vector3(0.0, 1.3, 0.9)
	add_child(glow)


func _add_box(size: Vector3, pos: Vector3, rot_deg: Vector3, mat: Material, solid: bool) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation_degrees = rot_deg
	if solid:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		cs.shape = shape
		body.add_child(cs)
		mi.add_child(body)
	add_child(mi)


func _build_trigger() -> void:
	var area := Area3D.new()
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interact_radius
	cs.shape = sphere
	cs.position.y = 1.0
	area.add_child(cs)
	add_child(area)
	area.body_entered.connect(func(body: Node3D) -> void: _set_near(body is Player, true))
	area.body_exited.connect(func(body: Node3D) -> void: _set_near(body is Player, false))


func _set_near(is_player: bool, near: bool) -> void:
	if not is_player or near == _near:
		return
	_near = near
	EventBus.shop_prompt_changed.emit(near)


func _unhandled_input(event: InputEvent) -> void:
	if _near and event.is_action_pressed("open_shop"):
		get_viewport().set_input_as_handled() # so the menu doesn't see this same press and close itself
		EventBus.shop_requested.emit()
