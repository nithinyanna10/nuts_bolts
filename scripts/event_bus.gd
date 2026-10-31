extends Node
## Game-wide events. Emitters and listeners never reference each other directly.

@warning_ignore("unused_signal")
signal screw_picked(base_value: int, world_position: Vector3)
@warning_ignore("unused_signal")
signal streak_changed(streak: int, multiplier: int)

@warning_ignore("unused_signal")
signal shop_prompt_changed(near: bool)
@warning_ignore("unused_signal")
signal shop_requested
@warning_ignore("unused_signal")
signal item_purchased(item_id: StringName)
@warning_ignore("unused_signal")
signal magnet_held_changed(held: int, cap: int)
@warning_ignore("unused_signal")
signal magnet_released(count: int, world_position: Vector3)
