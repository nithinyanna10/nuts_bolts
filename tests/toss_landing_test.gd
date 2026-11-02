extends SceneTree
## Run: godot --headless --path . -s tests/toss_landing_test.gd
## A tossed object's landing is planned at the throw and committed 0.5 s later. The world can change in between,
## so commit_landing must re-check the support height.

const FloatingCheck = preload("res://tests/floating_check.gd")
var _failures: int = 0


func _init() -> void:
	var cfg: DifficultyConfig = load("res://assets/data/easy.tres")
	_supporter_picked_up_mid_flight(cfg)
	_two_flights_to_the_same_spot(cfg)
	print("TOTAL FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _layout(cfg: DifficultyConfig) -> PileLayout:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var data: RoundData = ChallengeGenerator.new(cfg).generate(rng)
	var layout := PileLayout.new()
	layout.build(data, 0, rng)
	return layout


## A lands in the ring, B is planned on top of A, then A is picked up while B is still in the air.
func _supporter_picked_up_mid_flight(cfg: DifficultyConfig) -> void:
	var layout: PileLayout = _layout(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 2
	var spot := Vector3(layout.radius + 5.0, 0.0, 0.0) # far from the heap, nothing else here
	layout.remove_and_settle(0)
	layout.remove_and_settle(1)
	var land_a: Transform3D = layout.plan_landing(0, cfg, rng)
	land_a.origin = Vector3(spot.x, layout.half_vert[0], spot.z)
	layout.commit_landing(0, land_a)
	var land_b: Transform3D = layout.plan_landing(1, cfg, rng)
	land_b.origin = Vector3(spot.x, land_a.origin.y + layout.half_vert[0] + layout.half_vert[1], spot.z)
	layout.remove_and_settle(0) # the player picks A up during B's flight
	layout.commit_landing(1, land_b)
	var floating: int = FloatingCheck.flags(layout).count(1)
	if floating > 0:
		_fail("supporter picked up mid-flight: %d objects float (B at y=%.3f, floor is %.3f)" % [floating, layout.grid.positions[1].y, layout.half_vert[1]])


## Two objects planned for the same empty spot: the second to land must come to rest on the first.
func _two_flights_to_the_same_spot(cfg: DifficultyConfig) -> void:
	var layout: PileLayout = _layout(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 3
	var spot := Vector3(layout.radius + 5.0, 0.0, 0.0)
	layout.remove_and_settle(0)
	layout.remove_and_settle(1)
	var land_a: Transform3D = layout.plan_landing(0, cfg, rng)
	var land_b: Transform3D = layout.plan_landing(1, cfg, rng)
	land_a.origin = Vector3(spot.x, layout.half_vert[0], spot.z) # both planned while the spot was empty
	land_b.origin = Vector3(spot.x, layout.half_vert[1], spot.z)
	layout.commit_landing(0, land_a)
	layout.commit_landing(1, land_b)
	var gap: float = layout.grid.positions[1].y - (layout.grid.positions[0].y + layout.half_vert[0] + layout.half_vert[1])
	if gap < -0.002:
		_fail("two flights to one spot overlap: B sits %.3f m inside A" % -gap)


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL: " + msg)
