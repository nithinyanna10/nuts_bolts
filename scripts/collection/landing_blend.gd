extends RefCounted
## Drawn landing height of a tossed object. Pure maths, kept apart from HandController so it can be tested headless.
## Use: const LandingBlend = preload("res://scripts/collection/landing_blend.gd")


## Height at flight fraction t: the planned height until `start`, then eased to the height the object will really rest at
## (the world may have changed since the throw), reaching it exactly at t = 1 so landing never snaps.
static func y(planned: float, rest: float, t: float, start: float) -> float:
	if t >= 1.0:
		return rest
	if t <= start:
		return planned
	return lerpf(planned, rest, smoothstep(start, 1.0, t))
