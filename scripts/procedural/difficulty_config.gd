class_name DifficultyConfig
extends Resource
## All tunables for one difficulty. spec_props are the ObjDefs.Prop values an order may mention.

@export var display_name: String = "Easy"
@export var object_count: int = 150
@export var pile_count: int = 1
@export var spec_props: Array[int] = []
@export var target_types: Array[int] = [0, 1, 2, 3]
@export_range(0.0, 1.0) var near_miss_ratio: float = 0.4 ## share of distractors that differ in exactly one spec property
@export var target_cover_min: int = 0 ## objects dropped on top of the target
@export var target_cover_max: int = 2

@export_group("Round")
@export var base_payout: int = 20
@export var par_time: float = 60.0
@export var bonus_per_second: float = 0.5
@export var wrong_penalty_seconds: float = 5.0
@export var show_wrong_property: bool = true
@export var inspect_tools: bool = false ## ruler and thread gauge in the inspect view

@export_group("Pile")
@export var units_per_mm: float = 0.005 ## world meters per nominal mm (oversized on purpose)
@export var pile_slope: float = 0.7 ## repose slope of the mound (height / run)
@export var pile_packing: float = 0.22 ## object volume as a fraction of the mound cone; sets the pile radius
@export var pile_spread: float = 1.0
@export var pile_center_bias: float = 0.8 ## position radius = R * rand^bias; 0.5 = uniform, higher = denser center
@export var settle_time: float = 0.25 ## seconds for objects to drop after one is removed
@export var toss_distance_min: float = 0.3 ## tossed objects land this far beyond the pile edge...
@export var toss_distance_max: float = 1.4 ## ...up to this far
@export var grid_cell_size: float = 0.5


## "" if the generator can build rounds from this config, else what is wrong with it.
## Every check here guards a crash the config fuzz test found (tests/config_fuzz_test.gd).
func problem() -> String:
	if object_count < 1 or pile_count < 1:
		return "object_count and pile_count must be at least 1"
	if spec_props.is_empty():
		return "spec_props is empty (nothing to order)"
	for prop in spec_props:
		if prop < 0 or prop >= ObjDefs.PROP_COUNT:
			return "spec_props has %d, which is not an ObjDefs.Prop" % prop
	if spec_props.has(ObjDefs.Prop.LENGTH_CLASS) and spec_props.has(ObjDefs.Prop.LENGTH_MM):
		return "spec_props lists both LENGTH_CLASS and LENGTH_MM (the class jitter changes every length, so no object matches the exact one)"
	if target_types.is_empty():
		return "target_types is empty"
	for type in target_types:
		if not ObjDefs.TYPES.has(type):
			return "target_types has %d, which is not an ObjDefs.Type" % type
		# An order where nothing varies for this type leaves no object that differs from the target.
		if not spec_props.any(func(prop: int) -> bool: return ObjDefs.values(type, prop).size() > 1):
			return "no order property varies for target type %d" % type
	if target_cover_min < 0 or target_cover_max < target_cover_min:
		return "target_cover must satisfy 0 <= min <= max"
	# shortcut: only "> 0" is checked; a tiny positive grid_cell_size or units_per_mm builds slowly but does finish.
	if grid_cell_size <= 0.0 or units_per_mm <= 0.0 or pile_slope <= 0.0 or pile_packing <= 0.0 or pile_spread <= 0.0:
		return "grid_cell_size, units_per_mm, pile_slope, pile_packing and pile_spread must be above 0 (0 hangs the pile build)"
	return ""
