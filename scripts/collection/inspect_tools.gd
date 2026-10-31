class_name InspectTools
extends Node3D
## Ruler, caliper strip and thread gauge shown beside a held object (Hard and Expert).
## Child of the camera; origin = the object's head plane (zero line) on the object's axis.
## Everything is built at the object's scale, so lengths and thread spacing can be compared directly.

const SHADER: Shader = preload("res://assets/materials/ruler.gdshader")

@export var ruler_length_mm: int = 90
@export var ruler_width_mm: float = 14.0
@export var ruler_offset: float = 0.17 ## meters right of the object's axis
@export var caliper_length_mm: int = 30
@export var caliper_height_mm: float = 7.0
@export var caliper_lift: float = 0.07 ## meters above the zero line
@export var gauge_leaf_mm: Vector2 = Vector2(16.0, 7.0)
@export var gauge_offset: float = 0.3
@export var label_pixel_size: float = 0.0005
@export var label_font_size: int = 44

var length_world: float = 0.0 ## ruler length in meters, for framing


func build(units_per_mm: float, pitches: Array[int]) -> void:
	for child in get_children():
		child.queue_free()
	length_world = ruler_length_mm * units_per_mm
	var w: float = ruler_width_mm * units_per_mm

	# Vertical ruler: zero at the top (the head plane), numbers every 10 mm.
	_quad(Vector2(w, length_world), Vector3(ruler_offset + w / 2.0, -length_world / 2.0, 0.0), ruler_length_mm, false, 0.0)
	for mm in range(10, ruler_length_mm + 1, 10):
		_label(str(mm), Vector3(ruler_offset + w * 0.78, -mm * units_per_mm, 0.001))

	# Caliper strip above the head plane: read the shaft's width straight down onto it.
	var cw: float = caliper_length_mm * units_per_mm
	_quad(Vector2(cw, caliper_height_mm * units_per_mm), Vector3(0.0, caliper_lift, 0.0), caliper_length_mm, true, 0.0)
	for mm in range(0, caliper_length_mm + 1, 10):
		_label(str(mm), Vector3(-cw / 2.0 + mm * units_per_mm, caliper_lift + caliper_height_mm * units_per_mm * 0.85, 0.001))

	# Thread gauge leaves: teeth at each standard pitch.
	var lw: float = gauge_leaf_mm.x * units_per_mm
	var lh: float = gauge_leaf_mm.y * units_per_mm
	for i in pitches.size():
		var y: float = -0.16 - i * (lh + 0.045)
		_quad(Vector2(lw, lh), Vector3(gauge_offset + lw / 2.0, y, 0.0), int(gauge_leaf_mm.x), true, pitches[i] / 100.0)
		_label("%.2f" % (pitches[i] / 100.0), Vector3(gauge_offset + lw + 0.045, y, 0.001))


func _quad(size: Vector2, pos: Vector3, length_mm: int, horizontal: bool, pitch_mm: float) -> void:
	var mesh := QuadMesh.new()
	mesh.size = size
	var material := ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("length_mm", float(length_mm))
	material.set_shader_parameter("horizontal", horizontal)
	material.set_shader_parameter("pitch_mm", pitch_mm)
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = material
	node.position = pos
	node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(node)


func _label(text: String, pos: Vector3) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = label_font_size
	label.pixel_size = label_pixel_size
	label.outline_size = 8
	label.shaded = false
	label.modulate = Color(0.95, 0.9, 0.6)
	label.position = pos
	add_child(label)
