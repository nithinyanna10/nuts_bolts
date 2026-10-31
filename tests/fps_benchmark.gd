extends Node
## Windowed GPU benchmark (headless can't render):
##   godot --path . tests/fps_benchmark.tscn --resolution 1920x1080 [-- seconds=4 vsync=1 order=0,1,2,3]
## For each difficulty it builds a round and measures frame times from two viewpoints:
## "overview" (spawn point, all piles in view) and "close" (crouched at the target pile).

var _seconds: float = 4.0
var _vsync: bool = false
var _order: Array[int] = [0, 1, 2, 3]


func _ready() -> void:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("seconds="):
			_seconds = float(arg.get_slice("=", 1))
		elif arg == "vsync=1":
			_vsync = true
		elif arg.begins_with("order="):
			_order.clear()
			for item in arg.get_slice("=", 1).split(","):
				_order.append(int(item))
	if not _vsync: # set in-process: the --disable-vsync CLI flag was not reliable on macOS
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	get_tree().root.add_child.call_deferred(main)
	for i in 3:
		await get_tree().process_frame
	var first_round: RoundManager = main.get_node("RoundManager")
	while first_round._loading: # the game builds its first round on start
		await get_tree().process_frame
	var rm: RoundManager = main.get_node("RoundManager")
	var player: Player = main.get_node("Player")
	print("viewport %s, %s" % [get_viewport().get_visible_rect().size, RenderingServer.get_video_adapter_name()])
	print("%-8s %-9s %8s %9s %8s %7s %9s" % ["level", "view", "objects", "avg FPS", "1% low", "draws", "tris(k)"])
	for d in _order:
		await rm.start_round(d)
		await get_tree().create_timer(1.0).timeout
		var total: int = 0
		for pile in rm.piles:
			total += pile.object_count()
		await _measure(player, rm, d, "overview", total, false)
		await _measure(player, rm, d, "close", total, true)
	get_tree().quit()


func _measure(player: Player, rm: RoundManager, d: int, view: String, total: int, close: bool) -> void:
	var pile: ObjectPile = rm.piles[rm.data.pile_of[rm.data.target_index]]
	var head: Node3D = player.get_node("Head")
	if close:
		player.global_position = pile.global_position + Vector3(0.0, 0.05, pile.layout.radius + 1.2)
		head.position.y = 0.8
		head.rotation.x = -0.45
	else:
		player.global_position = Vector3(0.0, 0.1, 27.0)
		head.position.y = 1.6
		head.rotation.x = -0.25
	await get_tree().create_timer(1.0).timeout # warm up
	var times := PackedFloat32Array()
	var t_end: float = Time.get_ticks_msec() / 1000.0 + _seconds
	var last: int = Time.get_ticks_usec()
	while Time.get_ticks_msec() / 1000.0 < t_end:
		await get_tree().process_frame
		var now: int = Time.get_ticks_usec()
		times.append((now - last) / 1_000_000.0)
		last = now
	var sorted: Array = Array(times)
	sorted.sort()
	var avg: float = times.size() / maxf(_sum(times), 0.0001)
	var worst1: float = 0.0
	var n1: int = maxi(int(sorted.size() * 0.01), 1)
	for i in n1:
		worst1 += sorted[sorted.size() - 1 - i]
	var low1: float = 1.0 / (worst1 / n1)
	var draws: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME))
	var tris: int = int(RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME))
	var median: float = sorted[sorted.size() / 2] * 1000.0
	var capped: bool = absf(median - 8.33) < 0.5 or absf(median - 16.67) < 0.8 # sitting on a display refresh interval
	print("%-8s %-9s %8d %9.1f %8.1f %7d %9d  median %.2f ms%s" % [rm.data.config.display_name, view, total, avg, low1, draws, tris / 1000, median, "  [REFRESH-CAPPED: not a throughput number]" if capped else ""])


func _sum(values: PackedFloat32Array) -> float:
	var s: float = 0.0
	for v in values:
		s += v
	return s
