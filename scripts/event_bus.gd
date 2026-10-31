extends Node
## Game-wide events. Emitters and listeners never reference each other directly.

@warning_ignore("unused_signal")
signal screw_picked(base_value: int, world_position: Vector3)
@warning_ignore("unused_signal")
signal streak_changed(streak: int, multiplier: int)
