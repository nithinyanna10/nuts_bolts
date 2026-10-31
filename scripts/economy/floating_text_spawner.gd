class_name FloatingTextSpawner
extends Node
## Spawns a "+$N" label at each payout that drifts up and fades.

@export var rise_height: float = 0.9
@export var lifetime: float = 0.85
@export var spawn_offset: Vector3 = Vector3(0.0, 0.15, 0.0)
@export var font_size: int = 64
@export var pixel_size: float = 0.003
@export var outline_size: int = 14
@export var color: Color = Color(1.0, 0.88, 0.3)


func _ready() -> void:
	Economy.money_changed.connect(_on_money_changed)


func _on_money_changed(_total: int, amount: int, world_position: Vector3) -> void:
	var label := Label3D.new()
	label.text = "+$%d" % amount
	label.font_size = font_size
	label.pixel_size = pixel_size
	label.outline_size = outline_size
	label.outline_modulate = Color(0.0, 0.0, 0.0, 0.85)
	label.modulate = color
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.shaded = false
	label.top_level = true
	label.scale = Vector3.ONE * 0.4
	add_child(label)
	label.global_position = world_position + spawn_offset

	var tween: Tween = label.create_tween().set_parallel(true)
	tween.tween_property(label, "scale", Vector3.ONE, 0.15).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "position:y", label.position.y + rise_height, lifetime).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(label, "modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)
	tween.tween_property(label, "outline_modulate:a", 0.0, lifetime * 0.5).set_delay(lifetime * 0.5)
	tween.chain().tween_callback(label.queue_free)
