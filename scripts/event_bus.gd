extends Node
## Game-wide events. Emitters and listeners never reference each other directly.

@warning_ignore("unused_signal")
signal round_started(data: RoundData)
@warning_ignore("unused_signal")
signal round_clock(elapsed: float)
@warning_ignore("unused_signal")
signal round_finished(payout: int, elapsed: float)
@warning_ignore("unused_signal")
signal hud_message(text: String, positive: bool)
@warning_ignore("unused_signal")
signal inspect_changed(active: bool, fov: float)
@warning_ignore("unused_signal")
signal object_submitted(object_id: int)
@warning_ignore("unused_signal")
signal submission_result(correct: bool)
@warning_ignore("unused_signal")
signal shop_prompt_changed(near: bool)
@warning_ignore("unused_signal")
signal shop_requested
@warning_ignore("unused_signal")
signal item_purchased(item_id: StringName)
