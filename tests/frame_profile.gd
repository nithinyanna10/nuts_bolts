extends Node
## Windowed frame-spike profiler (headless can't render):
##   godot --path . tests/frame_profile.tscn --resolution 1920x1080 -- [novsync=1] [scenario=idle|play] [order=0,1,2,3] [seconds=4]
## Each frame is split into: script (process_frame -> pre_draw: all _process work), draw (pre_draw -> post_draw:
## rendering + present/vsync wait) and other (physics, OS wait). Frames carry the tag of what the "player" was doing,
## so a spike can be attributed. The "play" scenario drives the real input path: hover, pick, inspect, rotate,
## toss, wrong submit, quick-toss with settle.

var _scenario: String = "idle"
var _seconds: float = 4.0
var _order: Array[int] = [0, 1, 2, 3]
var _tag: String = "start"

var _t_frame: int = 0
var _t_pre: int = 0
var _t_post: int = 0
var _tags: Array[String] = []
var _dt := PackedFloat32Array()
var _script := PackedFloat32Array()
var _draw := PackedFloat32Array()
var _tag_idx := PackedInt32Array()


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_seconds = float(arg.get_slice("=", 1))
		elif arg.begins_with("order="):
			_order.clear()
			for s in arg.get_slice("=", 1).split(","):
				_order.append(int(s))
		elif arg.begins_with("scenario="):
			_scenario = arg.get_slice("=", 1)
		elif arg == "novsync=1":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in 3:
		await get_tree().process_frame
	var first_round: RoundManager = main.get_node("RoundManager")
	while first_round._loading: # the game builds its first round on start
		await get_tree().process_frame
	get_tree().process_frame.connect(_on_frame)
	RenderingServer.frame_pre_draw.connect(func() -> void: _t_pre = Time.get_ticks_usec())
	RenderingServer.frame_post_draw.connect(func() -> void: _t_post = Time.get_ticks_usec())
	print("vsync mode ", DisplayServer.window_get_vsync_mode(), "  scenario ", _scenario)
	var rm: RoundManager = main.get_node("RoundManager")
	for d in _order:
		_reset()
		var t0: int = Time.get_ticks_usec()
		_tag = "round_start"
		await rm.start_round(d) # builds over several frames; the per-frame stall shows in the frame stats
		var build_ms: float = (Time.get_ticks_usec() - t0) / 1000.0
		if _scenario == "play":
			await _play(main, rm)
		else:
			await _idle(main, rm)
		_report(rm.data.config.display_name, build_ms)
	get_tree().quit()


func _on_frame() -> void:
	var now: int = Time.get_ticks_usec()
	if _t_frame > 0 and _t_pre >= _t_frame and _t_post >= _t_pre:
		_dt.append((now - _t_frame) / 1000.0)
		_script.append((_t_pre - _t_frame) / 1000.0)
		_draw.append((_t_post - _t_pre) / 1000.0)
		if not _tags.has(_tag):
			_tags.append(_tag)
		_tag_idx.append(_tags.find(_tag))
	_t_frame = now


func _reset() -> void:
	_dt.clear()
	_script.clear()
	_draw.clear()
	_tag_idx.clear()
	_tags.clear()


func _wait(seconds: float, tag: String) -> void:
	_tag = tag
	var t_end: int = Time.get_ticks_usec() + int(seconds * 1_000_000.0)
	while Time.get_ticks_usec() < t_end:
		await get_tree().process_frame


func _idle(main: Node, rm: RoundManager) -> void:
	_aim_at_pile(main, rm)
	await _wait(_seconds, "idle")


# --- play scenario ---

func _aim_at_pile(main: Node, rm: RoundManager) -> ObjectPile:
	var pile: ObjectPile = rm.piles[rm.data.pile_of[rm.data.target_index]]
	var player: Player = main.get_node("Player")
	var head: Node3D = player.get_node("Head")
	player.global_position = pile.global_position + Vector3(0.0, 0.05, pile.layout.radius + 1.2)
	head.position.y = 0.8
	head.rotation.x = -0.45
	return pile


func _aim_at_top(main: Node, pile: ObjectPile) -> int:
	var best: int = -1
	for j in pile.object_count():
		if pile.is_active(j) and (best < 0 or pile.layout.grid.positions[j].y > pile.layout.grid.positions[best].y):
			best = j
	var player: Player = main.get_node("Player")
	var cam: Camera3D = main.get_node("Player/Head/Camera3D")
	var d: Vector3 = pile.object_world_center(best) - cam.global_position
	player.rotation.y = atan2(-d.x, -d.z)
	player.get_node("Head").rotation.x = atan2(d.y, Vector2(d.x, d.z).length())
	return best


func _tap(action: String) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	await get_tree().process_frame
	await get_tree().process_frame
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)


func _mouse(dx: float, dy: float) -> void:
	var ev := InputEventMouseMotion.new()
	ev.relative = Vector2(dx, dy)
	Input.parse_input_event(ev)


func _play(main: Node, rm: RoundManager) -> void:
	var pile: ObjectPile = _aim_at_pile(main, rm)
	var hc: HandController = main.get_node("Player/Head/Camera3D/HandController")
	await _wait(1.0, "idle")
	_aim_at_top(main, pile)
	await _wait(0.5, "first_hover")
	await _tap("pickup")
	await _wait(0.6, "pick_fly")
	await _wait(0.5, "inspect_still")
	_tag = "inspect_rotate"
	for i in 60:
		_mouse(8.0, 3.0)
		await get_tree().process_frame
	await _tap("submit") # wrong most of the time: penalty + auto toss
	await _wait(0.9, "toss_flight")
	for k in 6: # dig: quick-toss several objects, each triggers a settle
		_aim_at_top(main, pile)
		await _wait(0.15, "hover_next")
		await _tap("toss")
		await _wait(0.5, "quick_toss_settle")
	await _wait(1.0, "idle_after")


# --- report ---

func _report(label: String, build_ms: float) -> void:
	var n: int = _dt.size()
	if n == 0:
		print("== %s: no frames" % label)
		return
	var sorted: Array = Array(_dt)
	sorted.sort()
	var median: float = sorted[n / 2]
	var total: float = 0.0
	for v in _dt:
		total += v
	var n1: int = maxi(n / 100, 1)
	var worst: float = 0.0
	for i in n1:
		worst += sorted[n - 1 - i]
	# What a player feels: 1% low over the frames after loading (loading is behind the overlay).
	var played := PackedFloat32Array()
	for i in n:
		if _tags[_tag_idx[i]] != "round_start":
			played.append(_dt[i])
	var played_sorted: Array = Array(played)
	played_sorted.sort()
	var pn1: int = maxi(played.size() / 100, 1)
	var pworst: float = 0.0
	for i in pn1:
		pworst += played_sorted[played.size() - 1 - i]
	print("== %-7s build %.0f ms | %d frames avg %.0f FPS median %.2f ms p99 %.2f max %.1f | 1%% low %.1f FPS (%.1f excluding loading frames)" % [label, build_ms, n, n * 1000.0 / total, median, sorted[mini(int(n * 0.99), n - 1)], sorted[n - 1], 1000.0 / (worst / n1), 1000.0 / (pworst / pn1)])
	var threshold: float = maxf(median * 2.0, 6.0)
	var spikes: Dictionary = {}
	var by_phase := {"script": 0, "draw": 0, "other": 0}
	var spike_count: int = 0
	for i in n:
		if _dt[i] > threshold:
			spike_count += 1
			var other: float = _dt[i] - _script[i] - _draw[i]
			var phase: String = "script" if _script[i] >= _draw[i] and _script[i] >= other else ("draw" if _draw[i] >= other else "other")
			by_phase[phase] += 1
			var tag: String = _tags[_tag_idx[i]]
			spikes[tag] = spikes.get(tag, 0) + 1
	print("   spikes (> %.1f ms): %d  by dominant phase %s  by tag %s" % [threshold, spike_count, by_phase, spikes])
	# per-tag means so first-use costs stand out
	var line: String = "   per tag (frames / mean ms / max ms / mean script ms / max script ms):"
	for t in _tags.size():
		var cnt: int = 0
		var sum: float = 0.0
		var mx: float = 0.0
		var ssum: float = 0.0
		var smx: float = 0.0
		for i in n:
			if _tag_idx[i] == t:
				cnt += 1
				sum += _dt[i]
				mx = maxf(mx, _dt[i])
				ssum += _script[i]
				smx = maxf(smx, _script[i])
		line += "\n      %-18s %4d  %5.2f  %6.1f   %5.2f  %6.1f" % [_tags[t], cnt, sum / cnt, mx, ssum / cnt, smx]
	print(line)
