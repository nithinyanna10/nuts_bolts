class_name RoundData
extends RefCounted
## One generated round: per-object property columns (indexed by ObjDefs.Prop), pile assignment and the order.

var config: DifficultyConfig
var count: int = 0
var cols: Array[PackedInt32Array] = [] ## cols[prop][object]
var pile_of := PackedInt32Array()
var pile_objects: Array[PackedInt32Array] = [] ## object ids per pile, in the order they are dropped
var target_index: int = -1
var spec_props := PackedInt32Array() ## properties the order mentions (applicable to the target's type)
var spec_values := PackedInt32Array()


func value(i: int, prop: int) -> int:
	return cols[prop][i]


func matches_spec(i: int) -> bool:
	return first_difference(i) == -1


## First order property where object i differs from the order, or -1 if it matches.
func first_difference(i: int) -> int:
	for k in spec_props.size():
		if cols[spec_props[k]][i] != spec_values[k]:
			return spec_props[k]
	return -1


func order_lines() -> PackedStringArray:
	var lines := PackedStringArray()
	for k in spec_props.size():
		var prop: int = spec_props[k]
		lines.append("%s: %s" % [ObjDefs.prop_name(prop).capitalize(), ObjDefs.value_name(prop, spec_values[k])])
	return lines


## "Wrong drive: Phillips, not Torx" - what the object is vs what the order asked for.
func wrong_message(i: int, detailed: bool) -> String:
	var prop: int = first_difference(i)
	if prop == -1 or not detailed:
		return "Wrong."
	var wanted: int = spec_values[spec_props.find(prop)]
	return "Wrong %s: %s, not %s" % [ObjDefs.prop_name(prop), ObjDefs.value_name(prop, cols[prop][i]), ObjDefs.value_name(prop, wanted)]
