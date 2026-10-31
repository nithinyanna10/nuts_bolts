class_name ObjectPile
extends Node3D
## Renders one pile: one MultiMeshInstance3D per object variant (type, head, drive). Never one node per object.
## The pile node must stay unrotated and unscaled (picking assumes it).

const SHADER: Shader = preload("res://assets/materials/object.gdshader")
const HIDDEN: Transform3D = Transform3D(Basis(Vector3.ZERO, Vector3.ZERO, Vector3.ZERO), Vector3.ZERO)

@export var cast_shadows: bool = false

var data: RoundData
var layout := PileLayout.new()
var material: ShaderMaterial

var _variant := PackedInt32Array() ## variant key per local index
var _slot := PackedInt32Array() ## instance index within its variant's MultiMesh
var _scale := PackedFloat32Array() ## uniform mesh scale per object (m per mesh unit)
var _multimeshes: Dictionary = {} ## variant key -> MultiMesh
var _seen := PackedInt32Array()
var _stamp: int = 0
var _candidates := PackedInt32Array()
var _settle_time: float = 0.25
var _anim_j := PackedInt32Array()
var _anim_from := PackedFloat32Array()
var _anim_t := PackedFloat32Array()
var _hidden := PackedByteArray() ## 1 while an object is drawn elsewhere (held, hovered, in flight)
var _displayed_y: Dictionary = {} ## local index -> y currently drawn, only while settling
var last_hit_distance: float = 0.0
var _bound_center: Vector3 ## pile-local sphere that contains every object, including tossed ones
var _bound_radius: float = 0.0


func build(round_data: RoundData, pile_index: int, rng: RandomNumberGenerator) -> void:
	add_to_group("object_pile")
	data = round_data
	var cfg: DifficultyConfig = data.config
	_settle_time = cfg.settle_time
	layout.build(data, pile_index, rng)
	var n: int = layout.ids.size()
	_variant.resize(n)
	_slot.resize(n)
	_scale.resize(n)
	_seen.resize(n)
	_hidden.resize(n)

	material = ShaderMaterial.new()
	material.shader = SHADER
	material.set_shader_parameter("body_len", ObjDefs.BODY_LEN)

	var counts: Dictionary = {}
	for j in n:
		var g: int = layout.ids[j]
		var key: int = _variant_key(g)
		_variant[j] = key
		_slot[j] = counts.get(key, 0)
		counts[key] = _slot[j] + 1
		_scale[j] = cfg.units_per_mm * data.cols[ObjDefs.Prop.DIAMETER][g] / ObjDefs.REF_DIAMETER

	var reach: float = layout.radius + layout.max_foot * 2.0 + 1.0
	for key: int in counts:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.use_colors = true # colors and custom data must be enabled before instance_count
		mm.use_custom_data = true
		mm.mesh = ObjectMeshFactory.get_mesh(key / 10000, (key / 100) % 100, key % 100)
		mm.instance_count = counts[key]
		_multimeshes[key] = mm
		var node := MultiMeshInstance3D.new()
		node.multimesh = mm
		node.material_override = material
		node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if cast_shadows else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		node.custom_aabb = AABB(Vector3(-reach, -0.5, -reach), Vector3(reach * 2.0, 4.0, reach * 2.0)) # shaders move vertices
		add_child(node)

	var top: float = 0.0
	for p in layout.grid.positions:
		top = maxf(top, p.y)
	var ring: float = layout.radius + cfg.toss_distance_max + layout.max_foot * 2.0
	var height: float = top + layout.max_foot * 2.0 + 1.0 # room for tossed objects to stack
	_bound_center = Vector3(0.0, height / 2.0, 0.0)
	_bound_radius = sqrt(ring * ring + height * height / 4.0)

	for j in n:
		var g: int = layout.ids[j]
		var mm: MultiMesh = _multimeshes[_variant[j]]
		var tint: Color = ObjDefs.MATERIAL_COLORS[data.cols[ObjDefs.Prop.MATERIAL][g]]
		var v: float = rng.randf_range(0.9, 1.1)
		mm.set_instance_color(_slot[j], Color(tint.r * v, tint.g * v, tint.b * v, rng.randf()))
		mm.set_instance_custom_data(_slot[j], shader_data(g))
		show_object(j)


## (length factor, pitch in mesh units) for the shader; also used by the single promoted node.
func shader_data(g: int) -> Color:
	var c: Array[PackedInt32Array] = data.cols
	var s_d: float = c[ObjDefs.Prop.DIAMETER][g] / ObjDefs.REF_DIAMETER
	var factor: float = 1.0
	if ObjDefs.has_length(c[ObjDefs.Prop.TYPE][g]):
		factor = (c[ObjDefs.Prop.LENGTH_MM][g] / s_d - ObjDefs.TIP_H) / ObjDefs.BODY_LEN
	var pitch: float = c[ObjDefs.Prop.PITCH][g] / 100.0 / s_d
	return Color(factor, maxf(pitch, 0.01), 0.0, 0.0)


func object_count() -> int:
	return layout.ids.size()


func is_active(j: int) -> bool:
	return layout.active[j] == 1


## Local transform as drawn right now (follows a settle animation in progress).
func local_transform(j: int) -> Transform3D:
	var center: Vector3 = layout.grid.positions[j]
	if _displayed_y.has(j):
		center.y = _displayed_y[j]
	return Transform3D(layout.rot[j] * _scale[j], layout.origin_of(j, center))


func object_scale(j: int) -> float:
	return _scale[j]


func object_color(j: int) -> Color:
	return (_multimeshes[_variant[j]] as MultiMesh).get_instance_color(_slot[j])


func object_world_center(j: int) -> Vector3:
	return global_position + layout.grid.positions[j]


## World transform of the drawn object (includes the uniform mesh scale).
func world_transform(j: int) -> Transform3D:
	return global_transform * local_transform(j)


func show_object(j: int) -> void:
	_hidden[j] = 0
	(_multimeshes[_variant[j]] as MultiMesh).set_instance_transform(_slot[j], local_transform(j))


func hide_object(j: int) -> void:
	_hidden[j] = 1
	(_multimeshes[_variant[j]] as MultiMesh).set_instance_transform(_slot[j], HIDDEN)


## A tossed object comes to rest: back into the heap (grid, picking) at its planned spot.
func restore_object(j: int, landing: Transform3D) -> void:
	layout.commit_landing(j, landing)
	show_object(j)


## Landing spot for a tossed object, in pile-local space (see PileLayout.plan_landing).
func plan_landing(j: int, rng: RandomNumberGenerator) -> Transform3D:
	return layout.plan_landing(j, data.config, rng)


## Takes object j out of play (hidden for good) and animates whatever rested on it down.
func remove_object(j: int) -> void:
	var moved: PackedInt32Array = layout.remove_and_settle(j)
	hide_object(j)
	for i in moved.size():
		var k: int = moved[i]
		var idx: int = _anim_j.find(k)
		var start_y: float = _displayed_y.get(k, layout.moved_from_y[i])
		if idx >= 0:
			_anim_from[idx] = start_y
			_anim_t[idx] = 0.0
		else:
			_anim_j.append(k)
			_anim_from.append(start_y)
			_anim_t.append(0.0)
	set_process(not _anim_j.is_empty())


func _process(delta: float) -> void:
	var i: int = _anim_j.size() - 1
	while i >= 0:
		var j: int = _anim_j[i]
		_anim_t[i] = minf(_anim_t[i] + delta / maxf(_settle_time, 0.01), 1.0)
		var t: float = _anim_t[i]
		var e: float = t * t * (3.0 - 2.0 * t)
		var target: Vector3 = layout.grid.positions[j]
		var y: float = lerpf(_anim_from[i], target.y, e)
		_displayed_y[j] = y
		if _hidden[j] == 0:
			var xf := Transform3D(layout.rot[j] * _scale[j], layout.origin_of(j, Vector3(target.x, y, target.z)))
			(_multimeshes[_variant[j]] as MultiMesh).set_instance_transform(_slot[j], xf)
		if t >= 1.0:
			_displayed_y.erase(j)
			_anim_j.remove_at(i)
			_anim_from.remove_at(i)
			_anim_t.remove_at(i)
		i -= 1
	set_process(not _anim_j.is_empty())


## Nearest object (local index) hit by a world-space ray, or -1. Sets last_hit_distance.
## Marches along the ray, collecting objects from the 27 grid cells around each sample; each is tested as an OBB.
func pick_ray(origin: Vector3, direction: Vector3, max_distance: float) -> int:
	var o: Vector3 = to_local(origin)
	var d: Vector3 = global_basis.inverse() * direction
	# Cheap reject: skip piles whose bounding sphere the ray segment never touches.
	var along: float = clampf((_bound_center - o).dot(d), 0.0, max_distance)
	if (o + d * along).distance_squared_to(_bound_center) > _bound_radius * _bound_radius:
		last_hit_distance = max_distance
		return -1
	var step: float = layout.grid.cell_size * 0.4
	var best: int = -1
	var best_t: float = max_distance
	_stamp += 1
	var t: float = 0.0
	while t <= best_t + step:
		var n: int = layout.grid.neighbors_into(o + d * t, _candidates)
		for k in n:
			var j: int = _candidates[k]
			if _seen[j] == _stamp:
				continue
			_seen[j] = _stamp
			var hit: float = _ray_obb(j, o, d)
			if hit >= 0.0 and hit < best_t:
				best_t = hit
				best = j
		t += step
	last_hit_distance = best_t
	return best


func _ray_obb(j: int, o: Vector3, d: Vector3) -> float:
	var inv: Basis = layout.rot[j].transposed()
	var lo: Vector3 = inv * (o - layout.grid.positions[j])
	var ld: Vector3 = inv * d
	var h: Vector3 = layout.half[j]
	var t_min: float = 0.0
	var t_max: float = INF
	for a in 3:
		if absf(ld[a]) < 1e-6:
			if absf(lo[a]) > h[a]:
				return -1.0
		else:
			var t1: float = (-h[a] - lo[a]) / ld[a]
			var t2: float = (h[a] - lo[a]) / ld[a]
			t_min = maxf(t_min, minf(t1, t2))
			t_max = minf(t_max, maxf(t1, t2))
			if t_min > t_max:
				return -1.0
	return t_min


func _variant_key(g: int) -> int:
	var c: Array[PackedInt32Array] = data.cols
	return c[ObjDefs.Prop.TYPE][g] * 10000 + c[ObjDefs.Prop.HEAD][g] * 100 + c[ObjDefs.Prop.DRIVE][g]
