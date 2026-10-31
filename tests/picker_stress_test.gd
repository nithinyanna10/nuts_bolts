extends Node
## Run: godot --headless --path . tests/picker_stress_test.tscn
## Adversarial check of ObjectPile.pick_ray against brute force over every object's OBB: rays aimed end-on along long
## objects (their centers lie far behind their near ends), grazing rays, and random rays, on every difficulty.

const FILES: Array[String] = ["easy", "medium", "hard", "expert"]
var _failures: int = 0


func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for name in FILES:
		var cfg: DifficultyConfig = load("res://assets/data/%s.tres" % name)
		var data: RoundData = ChallengeGenerator.new(cfg).generate(rng)
		var pile := ObjectPile.new()
		add_child(pile)
		pile.build(data, 0, rng)
		var n: int = pile.object_count()
		var checked: int = 0
		var mismatches: int = 0
		var rays: int = mini(n, 1500) * 4
		for r in rays:
			var j: int = rng.randi() % n
			var center: Vector3 = pile.object_world_center(j)
			var axis: Vector3 = pile.layout.rot[j].y
			var origin: Vector3
			var target: Vector3 = center
			match r % 4:
				0: # end-on along the object's own axis, from beyond its near end
					origin = center + axis * (pile.layout.half[j].y + rng.randf_range(0.3, 1.2))
				1: # end-on from the other end
					origin = center - axis * (pile.layout.half[j].y + rng.randf_range(0.3, 1.2))
				2: # grazing: aimed at a point beside the object
					origin = center + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.3, 1.5), rng.randf_range(-1.0, 1.0))
					target = center + Vector3(rng.randf_range(-0.15, 0.15), 0.0, rng.randf_range(-0.15, 0.15))
				_: # random from above
					origin = center + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.5, 1.8), rng.randf_range(-1.0, 1.0))
			var dir: Vector3 = (target - origin).normalized()
			var best: int = -1
			var best_t: float = 4.0
			for k in n:
				var t: float = pile._ray_obb(k, pile.to_local(origin), dir)
				if t >= 0.0 and t < best_t:
					best_t = t
					best = k
			checked += 1
			var got: int = pile.pick_ray(origin, dir, 4.0)
			# Equal hit distance is a tie (origin inside two overlapping boxes), not a miss.
			var tie: bool = got >= 0 and best >= 0 and absf(pile._ray_obb(got, pile.to_local(origin), dir) - best_t) < 1e-5
			if got != best and not tie:
				mismatches += 1
				if mismatches <= 3:
					printerr("  %s: pick_ray %d vs brute force %d (ray kind %d)" % [name, got, best, r % 4])
		print("%-7s %5d objects, %5d rays: %d mismatches" % [name, n, checked, mismatches])
		_failures += mismatches
		pile.queue_free()
	print("TOTAL FAILURES: %d" % _failures)
	get_tree().quit(1 if _failures > 0 else 0)
