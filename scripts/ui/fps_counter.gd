extends Label
## FPS readout, debug builds only.


func _ready() -> void:
	visible = OS.is_debug_build()
	set_process(visible)


func _process(_delta: float) -> void:
	text = "%d FPS" % Engine.get_frames_per_second()
