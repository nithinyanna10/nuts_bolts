extends Node
## Game-wide events. Emitters and listeners never reference each other directly.

@warning_ignore("unused_signal")
signal round_started(data: RoundData)
@warning_ignore("unused_signal")
signal shop_prompt_changed(near: bool)
@warning_ignore("unused_signal")
signal shop_requested
@warning_ignore("unused_signal")
signal item_purchased(item_id: StringName)
