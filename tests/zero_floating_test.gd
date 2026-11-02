extends SceneTree
## Run: godot --headless --path . -s tests/zero_floating_test.gd [-- rounds=200]
## Builds every pile of N seeded rounds per difficulty and asserts nothing rests on nothing right after the build.
## Also checks the settle is idempotent and deterministic, and reports average pile height, width and build time.

const FloatingCheck = preload("res://tests/floating_check.gd")
const FILES: Array[String] = ["easy", "medium", "hard", "expert"]
var _failures: int = 0


func _init() -> void:
	var rounds: int = 200
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("rounds="):
			rounds = int(arg.substr(7))
	for name in FILES:
		var cfg: DifficultyConfig = load("res://assets/data/%s.tres" % name)
		var piles: int = 0
		var floating: int = 0
		var height_sum: float = 0.0
		var width_sum: float = 0.0
		var ms_sum: int = 0
		for seed_value in range(1, rounds + 1):
			var rng := RandomNumberGenerator.new()
			rng.seed = seed_value
			var data: RoundData = ChallengeGenerator.new(cfg).generate(rng)
			for k in cfg.pile_count:
				var t0: int = Time.get_ticks_msec()
				var layout := PileLayout.new()
				layout.build(data, k, rng)
				ms_sum += Time.get_ticks_msec() - t0
				piles += 1
				var n: int = FloatingCheck.flags(layout).count(1)
				floating += n
				if n > 0:
					_fail("%s seed %d pile %d: %d of %d objects rest on nothing" % [name, seed_value, k, n, layout.ids.size()])
				if layout.settle_all() != 0:
					_fail("%s seed %d pile %d: a second settle moved objects" % [name, seed_value, k])
				var top: float = 0.0
				var reach: float = 0.0
				for j in layout.ids.size():
					var p: Vector3 = layout.grid.positions[j]
					if is_nan(p.y) or p.y < layout.half_vert[j] - 0.001:
						_fail("%s seed %d pile %d: object %d at y=%.3f is below the floor" % [name, seed_value, k, j, p.y])
					top = maxf(top, p.y + layout.half_vert[j])
					reach = maxf(reach, Vector2(p.x, p.z).length() + layout.foot[j])
				height_sum += top
				width_sum += reach * 2.0
		_check_deterministic(cfg, name)
		print("%-7s %d rounds, %d piles: avg height %.3f m, avg width %.3f m, avg build %.1f ms/pile, %d objects resting on nothing" % [name, rounds, piles, height_sum / piles, width_sum / piles, float(ms_sum) / piles, floating])
	print("TOTAL FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


## The settle pass must not consume the RNG: the same seed gives the same layout twice.
func _check_deterministic(cfg: DifficultyConfig, name: String) -> void:
	var runs: Array[PackedVector3Array] = []
	for i in 2:
		var rng := RandomNumberGenerator.new()
		rng.seed = 1
		var data: RoundData = ChallengeGenerator.new(cfg).generate(rng)
		var layout := PileLayout.new()
		layout.build(data, 0, rng)
		runs.append(layout.grid.positions.duplicate())
	if runs[0] != runs[1]:
		_fail("%s: the same seed built two different piles" % name)


func _fail(msg: String) -> void:
	_failures += 1
	if _failures <= 10:
		printerr("FAIL: " + msg)
