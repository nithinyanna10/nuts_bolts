extends Node
## Soak test: plays N random rounds across all difficulties with simulated input and asserts the invariants.
##   godot --headless --path . tests/soak_test.tscn -- [rounds=50] [seed=1]
## Drives the real HandController / RoundManager / ObjectPile code (hover, pick, inspect, toss, quick-toss with settle,
## wrong submit, correct submit, abandoning a round mid-hold, double round requests). Headless cannot capture the mouse,
## so input goes through the controller's own action methods rather than key events.
## Asserts: no engine errors (Logger), no stuck states, target reachable by digging, no newly floating objects after
## settle, exactly one match per round, payout/penalty maths, no leaked nodes.

const SUPPORT_TOL: float = 0.02
const FLOOR_TOL: float = 0.01
## Known limitation, not a regression guard against zero: the heap placement rule can leave a few objects embedded
## beside a higher neighbour with nothing touching underneath (REPORT.md). Measured worst case is under 10%.
const MAX_UNSUPPORTED_SHARE: float = 0.15

class ErrorCatcher extends Logger:
	var errors: Array[String] = []

	func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool, _error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		errors.append("%s:%d %s %s (in %s)" % [file, line, code, rationale, function])


var _rng := RandomNumberGenerator.new()
var _failures: Array[String] = []
var _catcher := ErrorCatcher.new()
var _bus: Node
var _eco: Node
var _main: Node
var _rm: RoundManager
var _hc: HandController
var _player: Player
var _stats := {"rounds": 0, "picks": 0, "tosses": 0, "quick_tosses": 0, "wrong": 0, "correct": 0, "abandoned": 0, "dug": 0, "floating_checks": 0, "double_requests": 0}
var _unsupported_max: Dictionary = {} ## difficulty name -> worst share of objects with no support right after building
var _initial_floating: Dictionary = {} ## pile -> PackedByteArray of objects already unsupported when the pile was built


func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("FAIL: " + msg)


func _ready() -> void:
	var rounds: int = 50
	var seed_value: int = 1
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("rounds="):
			rounds = int(arg.get_slice("=", 1))
		elif arg.begins_with("seed="):
			seed_value = int(arg.get_slice("=", 1))
	_rng.seed = seed_value
	OS.add_logger(_catcher)
	_bus = get_tree().root.get_node("EventBus")
	_eco = get_tree().root.get_node("Economy")
	_main = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(_main)
	await get_tree().process_frame
	_rm = _main.get_node("RoundManager")
	_hc = _main.get_node("Player/Head/Camera3D/HandController")
	_player = _main.get_node("Player")
	await _bus.round_started # the game builds its first round on start
	var nodes_after_first: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	var t0: int = Time.get_ticks_msec()
	for r in rounds:
		await _run_round(r, _rng.randi() % 4)
	var nodes_end: int = int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))
	print("nodes: %d after first round, %d at end" % [nodes_after_first, nodes_end])
	if nodes_end > nodes_after_first * 3 + 200:
		_fail("node count grew from %d to %d (leak?)" % [nodes_after_first, nodes_end])
	for e in _catcher.errors:
		_fail("engine error: " + e)
	var shares: String = ""
	for k in _unsupported_max:
		shares += "%s %.1f%%  " % [k, _unsupported_max[k] * 100.0]
	print("worst share of objects resting on nothing right after a pile is built (physical plan-view rule): " + shares)
	print("soak: %d rounds in %.1fs, seed %d %s" % [rounds, (Time.get_ticks_msec() - t0) / 1000.0, seed_value, _stats])
	print("SOAK FAILURES: %d" % _failures.size())
	get_tree().quit(1 if not _failures.is_empty() else 0)


# --- one round ---

func _run_round(r: int, d: int) -> void:
	var tag: String = "round %d" % r
	var names: Array[String] = ["Easy", "Medium", "Hard", "Expert"]
	# Request the round twice: the second request while loading must be ignored.
	_rm.start_round(d)
	_rm.start_round((d + 1) % 4)
	_stats["double_requests"] += 1
	await _bus.round_started
	var data: RoundData = _rm.data
	tag += " (%s)" % names[d]
	if data.config.display_name != names[d]:
		_fail("%s: second start request was not ignored (got %s)" % [tag, data.config.display_name])
	_check_clean_start(tag)
	_check_one_match(tag, data)
	for pile in _rm.piles:
		var flags: PackedByteArray = _floating_flags(pile)
		_initial_floating[pile] = flags
		var unsupported: int = 0
		for f in flags:
			unsupported += f
		var share: float = float(unsupported) / maxf(pile.object_count(), 1)
		_unsupported_max[names[d]] = maxf(_unsupported_max.get(names[d], 0.0), share)
		if share > MAX_UNSUPPORTED_SHARE:
			_fail("%s: %.1f%% of a freshly built pile rests on nothing (limit %.0f%%)" % [tag, share * 100.0, MAX_UNSUPPORTED_SHARE * 100.0])
	_stats["rounds"] += 1

	var money_before: int = _eco.money
	var plan: float = _rng.randf()
	var target_pile: ObjectPile = _rm.piles[data.pile_of[data.target_index]]
	var dug: bool = false

	# Always: a pick + toss, then a wrong submit.
	await _pick_random_non_target(tag, target_pile)
	if _hc._state == HandController.State.INSPECT:
		_check_tools(tag, data)
		_hc._toss_held()
		_stats["tosses"] += 1
		await _flights_done(tag)
		_check_idle(tag)
	await _pick_random_non_target(tag, target_pile)
	if _hc._state == HandController.State.INSPECT:
		await _wrong_submit(tag, data)

	# Dig with quick-tosses (settle animations), checking nothing starts floating.
	for k in _rng.randi_range(3, 12):
		_quick_toss_random(tag, target_pile)
		await get_tree().process_frame
	await _settle_done(target_pile)
	_check_floating(tag, target_pile)

	await _flights_done(tag) # a quick-tossed object (possibly the target) is still in the air until it lands
	if plan < 0.15: # abandon: start the next round while holding something
		await _pick_random_non_target(tag, target_pile)
		_stats["abandoned"] += 1
		return
	if plan < 0.85:
		var ok: bool = await _dig_and_submit_target(tag, data, target_pile, money_before)
		dug = ok
	_stats["dug"] += 1 if dug else 0
	await _flights_done(tag)


# --- actions ---

func _exposed_object(pile: ObjectPile, exclude: int) -> int:
	# Aim rays from above at random points over the pile, like a player scanning it.
	for attempt in 40:
		var ang: float = _rng.randf() * TAU
		var rr: float = pile.layout.radius * sqrt(_rng.randf()) * 0.9
		var target: Vector3 = pile.global_position + Vector3(cos(ang) * rr, 0.1, sin(ang) * rr)
		var origin: Vector3 = target + Vector3(_rng.randf_range(-0.6, 0.6), _rng.randf_range(1.5, 2.5), _rng.randf_range(-0.6, 0.6))
		var j: int = pile.pick_ray(origin, (target - origin).normalized(), 5.0)
		if j >= 0 and j != exclude:
			return j
	return -1


func _pick_random_non_target(tag: String, pile: ObjectPile) -> void:
	if _hc._state != HandController.State.IDLE:
		_fail("%s: controller not idle before pick (state %d)" % [tag, _hc._state])
		return
	var target_j: int = pile.layout.ids.find(_rm.data.target_index)
	var j: int = _exposed_object(pile, target_j)
	if j < 0:
		return
	_hc._set_hover(pile, j)
	_hc._pick()
	_stats["picks"] += 1
	if not pile.layout.active[j] == 0:
		_fail("%s: picked object %d is still in the pile" % [tag, j])
	if not await _wait_until(func() -> bool: return _hc._state == HandController.State.INSPECT, 2.0):
		_fail("%s: never reached INSPECT after pick (state %d)" % [tag, _hc._state])
		return
	if not _player._locked:
		_fail("%s: player not locked while inspecting" % tag)
	_last_picked = [pile, j]


var _last_picked: Array = []


func _wrong_submit(tag: String, data: RoundData) -> void:
	var pile: ObjectPile = _last_picked[0]
	var j: int = _last_picked[1]
	var elapsed_before: float = _rm._elapsed
	var money_before: int = _eco.money
	var messages: Array[String] = []
	var catcher: Callable = func(text: String, _p: bool) -> void: messages.append(text)
	_bus.hud_message.connect(catcher)
	_hc._submit()
	_stats["wrong"] += 1
	await _flights_done(tag)
	_bus.hud_message.disconnect(catcher)
	var gained: float = _rm._elapsed - elapsed_before
	var penalty: float = data.config.wrong_penalty_seconds
	if gained < penalty or gained > penalty + 1.0:
		_fail("%s: wrong submit changed clock by %.2f, expected about %.1f" % [tag, gained, penalty])
	if _eco.money != money_before:
		_fail("%s: money changed on a wrong submit" % tag)
	if messages.size() != 1:
		_fail("%s: expected one message on wrong submit, got %s" % [tag, messages])
	elif data.config.show_wrong_property and not messages[0].begins_with("Wrong "):
		_fail("%s: bad detailed message %s" % [tag, messages[0]])
	elif not data.config.show_wrong_property and (not messages[0].begins_with("Wrong.") or ":" in messages[0]):
		_fail("%s: bad plain message %s" % [tag, messages[0]])
	if not pile.is_active(j):
		_fail("%s: wrongly submitted object did not land back in the pile" % tag)
	_check_idle(tag)


func _quick_toss_random(tag: String, pile: ObjectPile) -> void:
	if _hc._state != HandController.State.IDLE:
		return
	var j: int = _exposed_object(pile, -1)
	if j < 0:
		return
	_hc._set_hover(pile, j)
	_hc._quick_toss()
	_stats["quick_tosses"] += 1


## Digs with rays from above exactly like a player would: toss whatever blocks the target until a ray reaches it.
## Then picks it up and submits it. Returns true if the round was completed correctly.
func _dig_and_submit_target(tag: String, data: RoundData, pile: ObjectPile, money_before: int) -> bool:
	var tj: int = pile.layout.ids.find(data.target_index)
	if not pile.is_active(tj):
		_fail("%s: target is not in the pile before digging" % tag)
		return false
	var reachable: bool = false
	var tosses: int = 0
	for iter in pile.object_count() + 50:
		var c: Vector3 = pile.object_world_center(tj)
		var blocker: int = -1
		for s in 14:
			var origin: Vector3 = c + Vector3(_rng.randf_range(-0.5, 0.5), _rng.randf_range(0.8, 2.0), _rng.randf_range(-0.5, 0.5))
			var j: int = pile.pick_ray(origin, (c - origin).normalized(), 4.0)
			if j == tj:
				reachable = true
				break
			if j >= 0 and blocker < 0:
				blocker = j
		if reachable:
			break
		if blocker < 0:
			_fail("%s: no ray towards the target hit anything" % tag)
			return false
		pile.remove_object(blocker) # same calls the hand controller makes for a toss
		pile.restore_object(blocker, pile.plan_landing(blocker, _rng))
		tosses += 1
		if tosses % 8 == 0:
			await get_tree().process_frame
	if not reachable:
		_fail("%s: target unreachable after %d tosses" % [tag, tosses])
		return false
	await _settle_done(pile)
	_check_floating(tag, pile)
	_hc._set_hover(pile, tj)
	_hc._pick()
	if not await _wait_until(func() -> bool: return _hc._state == HandController.State.INSPECT, 2.0):
		_fail("%s: could not pick up the target (state %d)" % [tag, _hc._state])
		return false
	var elapsed_check: float = _rm._elapsed
	var payout_seen: Array[int] = []
	var finished: Callable = func(payout: int, _elapsed: float) -> void: payout_seen.append(payout)
	_bus.round_finished.connect(finished)
	_hc._submit()
	await get_tree().process_frame
	_bus.round_finished.disconnect(finished)
	_stats["correct"] += 1
	if _hc._state != HandController.State.FOUND:
		_fail("%s: state after the correct submit is %d, expected FOUND" % [tag, _hc._state])
	if payout_seen.size() != 1:
		_fail("%s: round_finished fired %d times" % [tag, payout_seen.size()])
		return false
	var cfg: DifficultyConfig = data.config
	var expected: int = cfg.base_payout + int(maxf(0.0, cfg.par_time - _rm._elapsed) * cfg.bonus_per_second)
	if payout_seen[0] != expected or _eco.money - money_before != expected:
		_fail("%s: payout %d, money delta %d, expected %d" % [tag, payout_seen[0], _eco.money - money_before, expected])
	if _rm._running:
		_fail("%s: round still running after a correct submit" % tag)
	# A second submit after the round ended must do nothing.
	var money_now: int = _eco.money
	_bus.object_submitted.emit(data.target_index)
	if _eco.money != money_now:
		_fail("%s: paid twice for one round" % tag)
	return true


# --- invariants ---

func _check_clean_start(tag: String) -> void:
	if _hc._state != HandController.State.IDLE:
		_fail("%s: controller state %d after a new round (expected IDLE)" % [tag, _hc._state])
	if _player._locked:
		_fail("%s: player still locked after a new round" % tag)
	if not _hc._flights.is_empty():
		_fail("%s: flights left over from the previous round" % tag)
	if _hc._flight_pool.size() != _hc.toss_pool_size:
		_fail("%s: flight pool has %d nodes, expected %d" % [tag, _hc._flight_pool.size(), _hc.toss_pool_size])
	if _hc._obj.visible:
		_fail("%s: hover/held node still visible after a new round" % tag)
	if _hc._piles.size() != _rm.piles.size():
		_fail("%s: hand controller knows %d piles, round has %d" % [tag, _hc._piles.size(), _rm.piles.size()])
	if _rm._loading or not _rm._running:
		_fail("%s: round manager not running after round_started" % tag)


func _check_idle(tag: String) -> void:
	if _hc._state != HandController.State.IDLE:
		_fail("%s: expected IDLE, controller is in state %d" % [tag, _hc._state])
	if _player._locked:
		_fail("%s: player left locked after leaving inspect" % tag)
	if not _hc._flights.is_empty():
		_fail("%s: %d flights still in the air" % [tag, _hc._flights.size()])


func _check_tools(tag: String, data: RoundData) -> void:
	if _hc._tools.visible != data.config.inspect_tools:
		_fail("%s: inspect tools visible=%s but config says %s" % [tag, _hc._tools.visible, data.config.inspect_tools])


func _check_one_match(tag: String, data: RoundData) -> void:
	var matches: int = 0
	for i in data.count:
		if data.matches_spec(i):
			matches += 1
	if matches != 1:
		_fail("%s: %d objects match the order" % [tag, matches])
	var in_piles: int = 0
	for pile in _rm.piles:
		in_piles += pile.object_count()
	if in_piles != data.count:
		_fail("%s: piles hold %d objects, round has %d" % [tag, in_piles, data.count])


## 1 for each active object that rests on nothing. Physical rule, independent of the layout's own: an object is
## supported if it is on the floor, or some lower object touches it in plan view (2D distance between their axis
## segments is below the sum of their radii) with no vertical gap above SUPPORT_TOL.
func _floating_flags(pile: ObjectPile) -> PackedByteArray:
	var l: PileLayout = pile.layout
	var flags := PackedByteArray()
	flags.resize(pile.object_count())
	for k in pile.object_count():
		if l.active[k] == 0:
			continue
		var p: Vector3 = l.grid.positions[k]
		if p.y - l.half_vert[k] <= FLOOR_TOL:
			continue
		var supported: bool = false
		var seg_k: PackedVector2Array = _segment(l, k)
		for m in l.grid.query(p, l.half[k].y + l.max_foot * 2.0 + l.half[k].x):
			var pm: Vector3 = l.grid.positions[m]
			if m == k or pm.y >= p.y:
				continue
			var gap: float = (p.y - l.half_vert[k]) - (pm.y + l.half_vert[m])
			if gap > SUPPORT_TOL:
				continue
			var seg_m: PackedVector2Array = _segment(l, m)
			if _segment_distance(seg_k[0], seg_k[1], seg_m[0], seg_m[1]) < l.half[k].x + l.half[m].x + 0.01:
				supported = true
				break
		flags[k] = 0 if supported else 1
	return flags


func _segment(l: PileLayout, k: int) -> PackedVector2Array:
	var c := Vector2(l.grid.positions[k].x, l.grid.positions[k].z)
	var axis := Vector2(l.rot[k].y.x, l.rot[k].y.z) * l.half[k].y
	return PackedVector2Array([c - axis, c + axis])


func _segment_distance(a0: Vector2, a1: Vector2, b0: Vector2, b1: Vector2) -> float:
	# Closest distance between two 2D segments (they intersect => 0).
	var best: float = INF
	for pair in [[a0, b0, b1], [a1, b0, b1], [b0, a0, a1], [b1, a0, a1]]:
		var pt: Vector2 = pair[0]
		var closest: Vector2 = Geometry2D.get_closest_point_to_segment(pt, pair[1], pair[2])
		best = minf(best, pt.distance_to(closest))
	if Geometry2D.segment_intersects_segment(a0, a1, b0, b1) != null:
		return 0.0
	return best


func _check_floating(tag: String, pile: ObjectPile) -> void:
	_stats["floating_checks"] += 1
	var now: PackedByteArray = _floating_flags(pile)
	var before: PackedByteArray = _initial_floating[pile]
	var fresh: int = 0
	var total: int = 0
	var worst: int = -1
	for k in now.size():
		total += now[k]
		if now[k] == 1 and before[k] == 0:
			fresh += 1
			worst = k
	if fresh > 0:
		var p: Vector3 = pile.layout.grid.positions[worst]
		_fail("%s: %d objects are floating after settle that were supported at the start (e.g. object %d at y=%.3f)" % [tag, fresh, worst, p.y])


# --- waiting ---

func _wait_until(cond: Callable, timeout: float) -> bool:
	var t_end: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < t_end:
		if cond.call():
			return true
		await get_tree().process_frame
	return cond.call()


func _flights_done(tag: String) -> void:
	if not await _wait_until(func() -> bool: return _hc._flights.is_empty() and _hc._state != HandController.State.PICKING, 3.0):
		_fail("%s: flights/pick animation never finished (%d flights, state %d)" % [tag, _hc._flights.size(), _hc._state])


func _settle_done(pile: ObjectPile) -> void:
	await _wait_until(func() -> bool: return pile._anim_j.is_empty(), 2.0)
	if not pile._anim_j.is_empty():
		_fail("settle animation never finished (%d objects still moving)" % pile._anim_j.size())
