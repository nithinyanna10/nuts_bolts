extends Node
## Run: godot --headless --path . tests/round_flow_test.tscn
## Drives one Easy round through the real scenes: ray picking, wrong submit (penalty + toss), correct submit (payout).

var _failures: int = 0
var _messages: Array[String] = []


func _fail(msg: String) -> void:
	_failures += 1
	printerr("FAIL: " + msg)


func _ready() -> void:
	var difficulty: int = 0
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("difficulty="):
			difficulty = int(arg.get_slice("=", 1))
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	main.get_node("RoundManager").start_difficulty = difficulty
	get_tree().root.add_child.call_deferred(main)
	await get_tree().process_frame
	var round_ready: Signal = get_tree().root.get_node("EventBus").round_started
	await round_ready # the round builds over several frames behind the loading overlay
	var eco: Node = get_tree().root.get_node("Economy")
	var bus: Node = get_tree().root.get_node("EventBus")
	bus.hud_message.connect(func(text: String, _p: bool) -> void: _messages.append(text))
	var rm: RoundManager = main.get_node("RoundManager")
	var hc: HandController = main.get_node("Player/Head/Camera3D/HandController")
	var player: Player = main.get_node("Player")
	var data: RoundData = rm.data
	var pile: ObjectPile = rm.piles[data.pile_of[data.target_index]] # the pile holding the target
	var target_j: int = pile.layout.ids.find(data.target_index)
	print("difficulty ", data.config.display_name, ": ", pile.object_count(), " objects in target pile, ", rm.piles.size(), " piles | ", " | ".join(data.order_lines()), " | target local ", target_j, " of ", pile.object_count())

	# 1. Ray picking: the grid-marched result must equal the brute-force nearest OBB hit, for random rays.
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	var exact: int = 0
	var hits: int = 0
	for r in 400:
		var j: int = rng.randi() % pile.object_count()
		var center: Vector3 = pile.object_world_center(j)
		var origin: Vector3 = center + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.5, 1.5), rng.randf_range(-1.0, 1.0))
		var dir: Vector3 = (center + Vector3(rng.randf_range(-0.2, 0.2), 0.0, rng.randf_range(-0.2, 0.2)) - origin).normalized()
		var brute: int = -1
		var best_t: float = 4.0
		for k in pile.object_count():
			var t: float = pile._ray_obb(k, pile.to_local(origin), dir)
			if t >= 0.0 and t < best_t:
				best_t = t
				brute = k
		var got: int = pile.pick_ray(origin, dir, 4.0)
		if brute >= 0:
			hits += 1
		if got != brute:
			_fail("pick_ray gave %d, brute force %d" % [got, brute])
		else:
			exact += 1
	print("picking: %d/400 rays agree with brute force (%d of them hit something)" % [exact, hits])
	if hits < 100:
		_fail("test rays barely hit anything")

	# 1b. Bounding-sphere reject: after many tosses (objects stacked in the ring beyond the pile), rays must give
	# exactly the same answer with the reject disabled.
	for i in 300:
		var tj: int = rng.randi() % pile.object_count()
		if pile.is_active(tj):
			pile.remove_object(tj)
			pile.restore_object(tj, pile.plan_landing(tj, rng))
	var culled_mismatch: int = 0
	var saved_radius: float = pile._bound_radius
	for r in 300:
		var center: Vector3 = pile.global_position + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.0, 0.8), rng.randf_range(-1.0, 1.0)) * (pile.layout.radius + 1.5)
		var origin: Vector3 = center + Vector3(rng.randf_range(-1.0, 1.0), rng.randf_range(0.8, 2.0), rng.randf_range(-1.0, 1.0))
		var dir: Vector3 = (center - origin).normalized()
		var with_reject: int = pile.pick_ray(origin, dir, 4.0)
		pile._bound_radius = 1e9
		var without: int = pile.pick_ray(origin, dir, 4.0)
		pile._bound_radius = saved_radius
		if with_reject != without:
			culled_mismatch += 1
	print("bounds reject: %d/300 rays differ from the unculled picker" % culled_mismatch)
	if culled_mismatch > 0:
		_fail("bounding reject changed pick results")
	# Loading guards: bad requests must not wedge the round manager.
	var piles_before: int = rm.piles.size()
	var data_before: RoundData = rm.data
	for bad in [99, -1]:
		rm.start_round(bad)
		if rm._loading:
			_fail("difficulty %d left the round manager loading" % bad)
	if rm.data != data_before or rm.piles.size() != piles_before or not rm._running:
		_fail("a rejected start_round disturbed the running round")
	var saved_anchors: Array[Vector3] = rm.pile_anchors.duplicate()
	rm.pile_anchors = []
	rm.start_round(0)
	rm.pile_anchors = saved_anchors
	if rm._loading or rm.data != data_before:
		_fail("too few pile anchors was not rejected cleanly")

	# 2. Wrong submit: pick a non-target, submit it, expect penalty message and the object back in the pile.
	player.global_position = pile.global_position + Vector3(0, 0.1, 2.0)
	var wrong_j: int = (target_j + 1) % pile.object_count()
	hc._set_hover(pile, wrong_j)
	hc._pick()
	await get_tree().create_timer(0.5).timeout
	if hc._state != HandController.State.INSPECT:
		_fail("not inspecting after pick (state %d)" % hc._state)
	if pile.is_active(wrong_j):
		_fail("picked object still in the pile")
	bus.object_submitted.emit(pile.layout.ids[wrong_j])
	await get_tree().create_timer(0.1).timeout
	print("wrong submit message: ", _messages)
	var detailed: bool = data.config.show_wrong_property
	if _messages.is_empty():
		_fail("no wrong-submit message")
	elif detailed and not _messages[0].begins_with("Wrong ") or not detailed and not _messages[0].begins_with("Wrong."):
		_fail("wrong message format for this difficulty: %s" % _messages[0])
	elif not detailed and ":" in _messages[0]:
		_fail("hard/expert must not say which property was wrong: %s" % _messages[0])
	if eco.money != 0:
		_fail("money changed on wrong submit")
	await get_tree().create_timer(0.8).timeout
	if not pile.is_active(wrong_j):
		_fail("tossed object did not land back in the pile area")
	if hc._state != HandController.State.IDLE:
		_fail("not idle after toss")

	# 3. Correct submit.
	hc._set_hover(pile, target_j)
	hc._pick()
	await get_tree().create_timer(0.5).timeout
	bus.object_submitted.emit(data.target_index)
	await get_tree().create_timer(0.1).timeout
	print("money after win: ", eco.money, " state: ", hc._state)
	if eco.money <= 0:
		_fail("no payout")
	if hc._state != HandController.State.FOUND:
		_fail("not in FOUND state")
	print("FAILURES: ", _failures)
	get_tree().quit(1 if _failures > 0 else 0)
