extends SceneTree
## Run: godot --headless --path . -s tests/config_fuzz_test.gd [-- configs=3000 seed=1]
## Throws random and edge-case DifficultyConfigs at problem(), the generator and the pile layout. For every config
## either problem() rejects it, or the generator must run with no engine error, give a valid round, and every pile of it
## must build (a bad layout field such as grid_cell_size = 0 used to hang the build forever).

const ErrorCatcher = preload("res://tests/error_catcher.gd")
var _failures: int = 0


func _init() -> void:
	var count: int = 3000
	var seed_value: int = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("configs="):
			count = int(arg.get_slice("=", 1))
		elif arg.begins_with("seed="):
			seed_value = int(arg.get_slice("=", 1))
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var accepted: int = 0
	var rejected: int = 0
	for i in count:
		var cfg: DifficultyConfig = _random_config(rng)
		if cfg.problem() != "":
			rejected += 1
			continue
		accepted += 1
		var before: int = catcher.errors.size()
		var gen_rng := RandomNumberGenerator.new()
		gen_rng.seed = seed_value * 100000 + i
		var data: RoundData = ChallengeGenerator.new(cfg).generate(gen_rng)
		if catcher.errors.size() > before:
			_fail("config %d accepted by problem() but the generator errored: %s | %s" % [i, _describe(cfg), catcher.errors[before]])
			continue
		if not _valid(data, cfg):
			_fail("config %d accepted by problem() but the round is invalid: %s" % [i, _describe(cfg)])
			continue
		for k in cfg.pile_count:
			var layout := PileLayout.new()
			layout.build(data, k, gen_rng)
			for p in layout.grid.positions:
				if not p.is_finite():
					_fail("config %d pile %d has a non-finite position: %s" % [i, k, _describe(cfg)])
					break
		if catcher.errors.size() > before:
			_fail("config %d accepted by problem() but a pile build errored: %s | %s" % [i, _describe(cfg), catcher.errors[before]])
	OS.remove_logger(catcher)
	print("%d configs: %d accepted by problem() and generated, %d rejected" % [count, accepted, rejected])
	if accepted < count / 20 or rejected < count / 20:
		_fail("fuzz is lopsided (%d accepted, %d rejected): it would pass vacuously" % [accepted, rejected])
	for name in ["easy", "medium", "hard", "expert"]:
		var shipped: DifficultyConfig = load("res://assets/data/%s.tres" % name)
		if shipped.problem() != "":
			_fail("shipped config %s rejected: %s" % [name, shipped.problem()])
	print("TOTAL FAILURES: %d" % _failures)
	quit(1 if _failures > 0 else 0)


func _random_config(rng: RandomNumberGenerator) -> DifficultyConfig:
	var cfg := DifficultyConfig.new()
	cfg.spec_props = _int_list(rng, -2, ObjDefs.PROP_COUNT + 2, 6)
	cfg.target_types = _int_list(rng, -1, 5, 5)
	cfg.object_count = _pick(rng, [-3, 0, 1, 2, 3, 7, 20, 60])
	cfg.pile_count = _pick(rng, [-2, 0, 1, 2, 3, 5, 8])
	cfg.target_cover_min = _pick(rng, [-3, 0, 0, 1, 2, 6])
	cfg.target_cover_max = _pick(rng, [-1, 0, 2, 2, 4, 6])
	cfg.near_miss_ratio = _pick(rng, [-0.5, 0.0, 0.2, 0.4, 0.7, 1.0, 1.5])
	cfg.grid_cell_size = _pick(rng, [-1.0, 0.0, 0.25, 0.5, 1.0, 3.0])
	cfg.units_per_mm = _pick(rng, [-1.0, 0.0, 0.003, 0.005, 0.01])
	cfg.pile_slope = _pick(rng, [-1.0, 0.0, 0.3, 0.7, 1.5])
	cfg.pile_packing = _pick(rng, [-1.0, 0.0, 0.1, 0.22, 0.6])
	cfg.pile_spread = _pick(rng, [-1.0, 0.0, 0.8, 1.0, 1.4])
	if rng.randf() < 0.5: # half of the configs start from something sane so that many are accepted
		cfg.spec_props = _int_list(rng, 0, ObjDefs.PROP_COUNT - 1, 5)
		cfg.target_types = _int_list(rng, 0, 3, 4)
		cfg.object_count = _pick(rng, [5, 20, 60, 200])
		cfg.pile_count = _pick(rng, [1, 2, 3])
		if rng.randf() < 0.7: # mostly sane layout fields, so most sane-order configs get as far as building piles
			cfg.grid_cell_size = 0.5
			cfg.units_per_mm = 0.005
			cfg.pile_slope = 0.7
			cfg.pile_packing = 0.22
			cfg.pile_spread = 1.0
	return cfg


## 0..max_len random ints in [lo, hi] (duplicates allowed, so empty lists and repeats both occur).
func _int_list(rng: RandomNumberGenerator, lo: int, hi: int, max_len: int) -> Array[int]:
	var out: Array[int] = []
	for i in rng.randi_range(0, max_len):
		out.append(rng.randi_range(lo, hi))
	return out


func _pick(rng: RandomNumberGenerator, values: Array) -> Variant:
	return values[rng.randi() % values.size()]


## Exactly `count` objects, exactly one matches the order, each object sits in exactly one pile.
func _valid(data: RoundData, cfg: DifficultyConfig) -> bool:
	if data == null or data.count != cfg.object_count or data.pile_objects.size() != cfg.pile_count:
		return false
	var matches: int = 0
	for i in data.count:
		matches += 1 if data.matches_spec(i) else 0
	var seen := PackedInt32Array()
	seen.resize(data.count)
	for list in data.pile_objects:
		for id in list:
			seen[id] += 1
	return matches == 1 and seen.count(1) == data.count


func _describe(cfg: DifficultyConfig) -> String:
	return "spec=%s targets=%s objects=%d piles=%d cover=%d..%d cell=%s mm=%s slope=%s packing=%s spread=%s" % [cfg.spec_props, cfg.target_types, cfg.object_count, cfg.pile_count, cfg.target_cover_min, cfg.target_cover_max, cfg.grid_cell_size, cfg.units_per_mm, cfg.pile_slope, cfg.pile_packing, cfg.pile_spread]


func _fail(msg: String) -> void:
	_failures += 1
	if _failures <= 10:
		printerr("FAIL: " + msg)
