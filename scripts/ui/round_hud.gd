extends Control
## Order card, round clock, feedback messages and the round-complete banner.

@export var message_time: float = 2.5
@export var good_color: Color = Color(0.45, 1.0, 0.55)
@export var bad_color: Color = Color(1.0, 0.4, 0.3)

var _message_tween: Tween

@onready var _title: Label = $Order/Margin/VBox/Title
@onready var _lines: Label = $Order/Margin/VBox/Lines
@onready var _clock: Label = $Order/Margin/VBox/Clock
@onready var _message: Label = $Message
@onready var _result: Label = $Result


func _ready() -> void:
	_message.modulate.a = 0.0
	_result.visible = false
	EventBus.round_started.connect(_on_round_started)
	EventBus.round_clock.connect(_on_clock)
	EventBus.round_finished.connect(_on_round_finished)
	EventBus.hud_message.connect(_on_message)


func _on_round_started(data: RoundData) -> void:
	_title.text = "ORDER  -  %s" % data.config.display_name.to_upper()
	_lines.text = "\n".join(data.order_lines())
	_result.visible = false
	_message.modulate.a = 0.0


func _on_clock(elapsed: float) -> void:
	_clock.text = "%d:%04.1f" % [int(elapsed) / 60, fmod(elapsed, 60.0)]


func _on_round_finished(payout: int, elapsed: float) -> void:
	_result.text = "FOUND IT!   +$%d\n%.1f s   -   press 1-4 for a new round" % [payout, elapsed]
	_result.visible = true


func _on_message(text: String, positive: bool) -> void:
	_message.text = text
	_message.modulate = good_color if positive else bad_color
	if _message_tween:
		_message_tween.kill()
	_message_tween = create_tween()
	_message_tween.tween_interval(message_time * 0.6)
	_message_tween.tween_property(_message, "modulate:a", 0.0, message_time * 0.4)
