class_name ChallengeGenerator
extends RefCounted
## Builds rounds with exactly one object matching the order. Every other object differs from the
## target in at least one order property. Unlisted properties are fixed to defaults, so they add no noise.

const P := ObjDefs.Prop

var _config: DifficultyConfig
var _combo_cols: Array[PackedInt32Array] = [] ## every possible object under this config, per property
var _combo_count: int = 0
var _combos_by_type: Dictionary = {} ## type -> PackedInt32Array of combo ids


func _init(config: DifficultyConfig) -> void:
	_config = config
	for p in ObjDefs.PROP_COUNT:
		_combo_cols.append(PackedInt32Array())
	for type in ObjDefs.TYPES:
		_add_type_combos(type)


func generate(rng: RandomNumberGenerator) -> RoundData:
	var data := RoundData.new()
	data.config = _config
	data.count = _config.object_count

	var target_type: int = _config.target_types[rng.randi() % _config.target_types.size()]
	var type_combos: PackedInt32Array = _combos_by_type[target_type]
	var target_combo: int = type_combos[rng.randi() % type_combos.size()]

	# The order lists the configured properties that vary for the target's type.
	for p: int in _config.spec_props:
		if p == P.TYPE or ObjDefs.values(target_type, p).size() > 1:
			data.spec_props.append(p)
			data.spec_values.append(_combo_cols[p][target_combo])

	# Near-misses differ from the order in exactly one property; "far" is every non-matching combo.
	var near := PackedInt32Array()
	var far := PackedInt32Array()
	for c in _combo_count:
		var diff: int = _diff_count(c, data)
		if diff > 0:
			far.append(c)
			if diff == 1:
				near.append(c)

	var picks := PackedInt32Array()
	picks.resize(data.count)
	picks[0] = target_combo # object 0 is the target; piles are shuffled so the id leaks nothing
	for i in range(1, data.count):
		var pool: PackedInt32Array = near if (not near.is_empty() and rng.randf() < _config.near_miss_ratio) else far
		picks[i] = pool[rng.randi() % pool.size()]

	for p in ObjDefs.PROP_COUNT:
		var col := PackedInt32Array()
		col.resize(data.count)
		for i in data.count:
			col[i] = _combo_cols[p][picks[i]]
		data.cols.append(col)
	_jitter_lengths(data, rng)
	data.target_index = 0
	_build_piles(data, rng)
	return data


func _add_type_combos(type: int) -> void:
	var combos: Array[PackedInt32Array] = []
	var base := PackedInt32Array()
	base.resize(ObjDefs.PROP_COUNT)
	base[P.TYPE] = type
	combos.append(base)
	for p: int in [P.HEAD, P.DRIVE, P.MATERIAL, P.DIAMETER, P.PITCH]:
		combos = _expand(combos, p, _listed(type, p))
	# Length is two columns (mm, class) that must agree.
	var length_pairs: Array[Vector2i] = []
	if not ObjDefs.has_length(type):
		length_pairs.append(Vector2i(0, ObjDefs.LenClass.NONE))
	elif _config.spec_props.has(P.LENGTH_CLASS):
		for cls in ObjDefs.values(type, P.LENGTH_CLASS):
			var band: Vector2i = ObjDefs.CLASS_BAND_MM[cls]
			length_pairs.append(Vector2i((band.x + band.y) / 2, cls))
	elif _config.spec_props.has(P.LENGTH_MM):
		for mm in ObjDefs.LENGTHS_MM:
			length_pairs.append(Vector2i(mm, ObjDefs.length_class(mm)))
	else:
		length_pairs.append(Vector2i(ObjDefs.DEFAULT_LENGTH_MM, ObjDefs.LenClass.MEDIUM))
	var ids := PackedInt32Array()
	for combo in combos:
		for pair in length_pairs:
			combo[P.LENGTH_MM] = pair.x
			combo[P.LENGTH_CLASS] = pair.y
			for p in ObjDefs.PROP_COUNT:
				_combo_cols[p].append(combo[p])
			ids.append(_combo_count)
			_combo_count += 1
	_combos_by_type[type] = ids


func _listed(type: int, prop: int) -> Array[int]:
	if _config.spec_props.has(prop):
		return ObjDefs.values(type, prop)
	return [ObjDefs.default_value(type, prop)]


func _expand(combos: Array[PackedInt32Array], prop: int, vals: Array[int]) -> Array[PackedInt32Array]:
	var out: Array[PackedInt32Array] = []
	for combo in combos:
		for v in vals:
			var next := combo.duplicate()
			next[prop] = v
			out.append(next)
	return out


func _diff_count(c: int, data: RoundData) -> int:
	var diff: int = 0
	for k in data.spec_props.size():
		if _combo_cols[data.spec_props[k]][c] != data.spec_values[k]:
			diff += 1
	return diff


## Class orders (Easy/Medium): give each object a real length inside its class band, so lengths vary a little.
func _jitter_lengths(data: RoundData, rng: RandomNumberGenerator) -> void:
	if not _config.spec_props.has(P.LENGTH_CLASS):
		return
	var lengths: PackedInt32Array = data.cols[P.LENGTH_MM]
	var classes: PackedInt32Array = data.cols[P.LENGTH_CLASS]
	for i in data.count:
		if classes[i] != ObjDefs.LenClass.NONE:
			var band: Vector2i = ObjDefs.CLASS_BAND_MM[classes[i]]
			lengths[i] = rng.randi_range(band.x, band.y)
	data.cols[P.LENGTH_MM] = lengths


## Deals objects to piles (target to a random one), shuffles each pile's drop order, then drops the
## target so that a random number of objects (cover) lands on it. Only non-targets can ever cover it.
func _build_piles(data: RoundData, rng: RandomNumberGenerator) -> void:
	var piles: int = _config.pile_count
	var target_pile: int = rng.randi() % piles
	var lists: Array[PackedInt32Array] = []
	for k in piles:
		lists.append(PackedInt32Array())
	data.pile_of.resize(data.count)
	data.pile_of[data.target_index] = target_pile
	for i in data.count:
		if i != data.target_index:
			data.pile_of[i] = i % piles
			lists[data.pile_of[i]].append(i)
	for k in piles:
		var list: PackedInt32Array = lists[k]
		for j in range(list.size() - 1, 0, -1): # Fisher-Yates
			var r: int = rng.randi() % (j + 1)
			var t: int = list[j]
			list[j] = list[r]
			list[r] = t
		if k == target_pile:
			var cover: int = mini(rng.randi_range(_config.target_cover_min, _config.target_cover_max), list.size())
			list.insert(list.size() - cover, data.target_index)
		data.pile_objects.append(list)
