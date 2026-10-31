extends SceneTree
## Run: godot --headless --path . -s tests/challenge_generator_test.gd [-- rounds=1000 only=easy]
## Generates rounds per difficulty and asserts the guarantees from CLAUDE.md.

const P := ObjDefs.Prop
const FILES: Array[String] = ["easy", "medium", "hard", "expert"]

var _failures: int = 0


func _init() -> void:
	var rounds: int = 1000
	var only: String = ""
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("rounds="):
			rounds = int(arg.get_slice("=", 1))
		elif arg.begins_with("only="):
			only = arg.get_slice("=", 1)
	_check_bands()
	for name in FILES:
		if only != "" and only != name:
			continue
		var cfg: DifficultyConfig = load("res://assets/data/%s.tres" % name)
		var t0: int = Time.get_ticks_msec()
		_test_difficulty(name, cfg, rounds)
		print("%-7s %d rounds x %d objects: %s (%.1fs)" % [name, rounds, cfg.object_count, "OK" if _failures == 0 else "FAILURES", (Time.get_ticks_msec() - t0) / 1000.0])
	print("TOTAL FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _fail(msg: String) -> void:
	_failures += 1
	if _failures <= 10:
		printerr("FAIL: " + msg)


func _check_bands() -> void:
	var prev_hi: int = 0
	for cls in [ObjDefs.LenClass.SHORT, ObjDefs.LenClass.MEDIUM, ObjDefs.LenClass.LONG]:
		var band: Vector2i = ObjDefs.CLASS_BAND_MM[cls]
		if band.x <= prev_hi * 1.3:
			_fail("length class bands too close: %s" % band)
		prev_hi = band.y
		if ObjDefs.length_class(band.x) != cls or ObjDefs.length_class(band.y) != cls:
			_fail("class split disagrees with band %s" % band)


func _test_difficulty(name: String, cfg: DifficultyConfig, rounds: int) -> void:
	var gen := ChallengeGenerator.new(cfg)
	var rng := RandomNumberGenerator.new()
	rng.seed = 12345
	var hidden_props: Array[int] = [P.LENGTH_MM, P.DIAMETER, P.PITCH]
	for r in rounds:
		var d: RoundData = gen.generate(rng)
		var tag := "%s round %d" % [name, r]

		# Order only uses properties allowed at this difficulty.
		for p in d.spec_props:
			if not cfg.spec_props.has(p):
				_fail("%s: order uses unlisted property %d" % [tag, p])
			if (name == "easy" or name == "medium") and hidden_props.has(p):
				_fail("%s: hidden property %d in an easy/medium order" % [tag, p])
		if d.spec_props.is_empty():
			_fail("%s: empty order" % tag)

		# Exactly one match, and it is the target.
		var matches: int = 0
		for i in d.count:
			if d.matches_spec(i):
				matches += 1
				if i != d.target_index:
					_fail("%s: object %d matches but is not the target" % [tag, i])
			else:
				# Every distractor differs in a property listed on the order (so the player can check it).
				var diff: int = d.first_difference(i)
				if diff == -1 or not d.spec_props.has(diff):
					_fail("%s: distractor %d has no checkable difference" % [tag, i])
		if matches != 1:
			_fail("%s: %d objects match the order" % [tag, matches])

		# Object values are valid for their type; class and mm agree.
		for i in d.count:
			var type: int = d.cols[P.TYPE][i]
			for p in [P.HEAD, P.DRIVE, P.MATERIAL, P.DIAMETER, P.PITCH]:
				if not ObjDefs.values(type, p).has(d.cols[p][i]):
					_fail("%s: object %d invalid value for prop %d" % [tag, i, p])
					break
			if d.cols[P.LENGTH_CLASS][i] != ObjDefs.length_class(d.cols[P.LENGTH_MM][i]):
				_fail("%s: object %d length class disagrees with mm" % [tag, i])
		if d.count != cfg.object_count:
			_fail("%s: wrong object count %d" % [tag, d.count])

		# Piles: every object in exactly one pile; the target is in its own pile list, covered only by non-targets.
		var seen := PackedByteArray()
		seen.resize(d.count)
		for k in d.pile_objects.size():
			for id in d.pile_objects[k]:
				seen[id] += 1
				if d.pile_of[id] != k:
					_fail("%s: pile_of mismatch for %d" % [tag, id])
		for i in d.count:
			if seen[i] != 1:
				_fail("%s: object %d appears %d times in piles" % [tag, i, seen[i]])
				break
		var list: PackedInt32Array = d.pile_objects[d.pile_of[d.target_index]]
		var cover: int = list.size() - 1 - list.find(d.target_index)
		if cover < 0 or cover > cfg.target_cover_max:
			_fail("%s: target cover %d out of range" % [tag, cover])
		if d.pile_objects.size() != cfg.pile_count:
			_fail("%s: wrong pile count" % tag)
