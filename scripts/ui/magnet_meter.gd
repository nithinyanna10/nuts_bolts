extends Label
## Shows how many screws the magnet is holding, e.g. "37 / 50".

@export var full_color: Color = Color(1.0, 0.35, 0.2)
@export var punch_scale: float = 1.15
@export var punch_time: float = 0.08

var _tween: Tween


func _ready() -> void:
	pivot_offset = size / 2.0
	visible = false
	EventBus.magnet_held_changed.connect(_on_held_changed)


func _on_held_changed(held: int, cap: int) -> void:
	visible = held > 0
	text = "FULL  %d / %d" % [held, cap] if held >= cap else "%d / %d" % [held, cap]
	modulate = full_color if held >= cap else Color.WHITE
	if _tween:
		_tween.kill()
	scale = Vector2.ONE * punch_scale
	_tween = create_tween()
	_tween.tween_property(self, "scale", Vector2.ONE, punch_time)
