extends ColorRect
## Dark overlay with a short message while a round is being built.


func _ready() -> void:
	visible = false
	EventBus.loading_changed.connect(func(active: bool) -> void: visible = active)
