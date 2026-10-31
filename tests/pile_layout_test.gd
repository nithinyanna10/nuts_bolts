extends SceneTree
## Run: godot --headless --path . -s tests/pile_layout_test.gd
## Builds pile layouts for every difficulty; checks sane geometry and that removing objects only lowers others.

const FILES: Array[String] = ["easy", "medium", "hard", "expert"]
var _failures: int = 0


func _init() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for name in FILES:
		var cfg: DifficultyConfig = load("res://assets/data/%s.tres" % name)
		var data: RoundData = ChallengeGenerator.new(cfg).generate(rng)
		var t0: int = Time.get_ticks_msec()
		var total_max_y: float = 0.0
		var radius: float = 0.0
		for k in cfg.pile_count:
			var layout := PileLayout.new()
			layout.build(data, k, rng)
			var t_build: int = Time.get_ticks_msec() - t0
			radius = layout.radius
			var pos: PackedVector3Array = layout.grid.positions
			for j in pos.size():
				var p: Vector3 = pos[j]
				if is_nan(p.x) or is_nan(p.y) or p.y < layout.half_vert[j] - 0.001:
					_fail("%s: bad position %s" % [name, p])
					break
				total_max_y = maxf(total_max_y, p.y)
			# Remove 200 random objects (tall ones fall far); every settle may only lower objects, never below a supporter.
			var order: Array = range(pos.size())
			order.shuffle()
			var moved_total: int = 0
			for r in mini(200, order.size()):
				var j: int = order[r]
				var before: PackedVector3Array = layout.grid.positions.duplicate()
				var moved: PackedInt32Array = layout.remove_and_settle(j)
				moved_total += moved.size()
				var moved_flag := PackedByteArray()
				moved_flag.resize(pos.size())
				for m in moved:
					moved_flag[m] = 1 # objects that fell in this same settle rest on others, so they cannot be oracle supporters
				for i in moved.size():
					var m: int = moved[i]
					var after: Vector3 = layout.grid.positions[m]
					if after.y > before[m].y or after.y < layout.half_vert[m] - 0.001:
						_fail("%s: settle moved object %d from %.3f to %.3f" % [name, m, before[m].y, after.y])
					# Independent of the grid query: a moved object must not end up below any object that touches it and
					# was lower than it (brute force over every active object).
					var expected: float = layout.half_vert[m]
					for o in pos.size():
						var po: Vector3 = layout.grid.positions[o]
						if o != m and layout.active[o] == 1 and moved_flag[o] == 0 and po.y < layout.moved_from_y[i] and layout._touching(after, layout.rot[m], layout.half[m], po, layout.rot[o], layout.half[o]):
							expected = maxf(expected, po.y + layout.half_vert[o] + layout.half_vert[m])
					if after.y < expected - 0.002:
						_fail("%s: settle dropped object %d to %.3f, through a supporter (should rest at %.3f)" % [name, m, after.y, expected])
			print("%-7s pile %d: %d objects, radius %.2f m, max height %.2f m, settled %d objects over 200 removals, build+test %d ms" % [name, k, layout.ids.size(), radius, total_max_y, moved_total, Time.get_ticks_msec() - t0])
			t0 = Time.get_ticks_msec()
	print("TOTAL FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _fail(msg: String) -> void:
	_failures += 1
	if _failures <= 10:
		printerr("FAIL: " + msg)
