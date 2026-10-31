class_name RoundManager
extends Node3D
## Runs rounds: generates the order and piles, times the round, judges submissions and pays out.
## Money is earned only here, by finding the right object.

@export_file("*.tres") var difficulty_files: Array[String] = []
@export var pile_anchors: Array[Vector3] = []
@export var start_difficulty: int = 0

var data: RoundData
var piles: Array[ObjectPile] = []
var _config: DifficultyConfig
var _rng := RandomNumberGenerator.new()
var _elapsed: float = 0.0
var _running: bool = false
var _loading: bool = false


func _ready() -> void:
	_rng.randomize()
	EventBus.object_submitted.connect(_on_object_submitted)
	start_round(start_difficulty)


func _process(delta: float) -> void:
	if _running:
		_elapsed += delta
		EventBus.round_clock.emit(_elapsed)


func _unhandled_input(event: InputEvent) -> void:
	for i in difficulty_files.size():
		if event.is_action_pressed("round_%d" % (i + 1)):
			start_round(i)


## Builds a round behind the loading overlay, one pile per frame, so no single frame stalls
## (Expert used to freeze for ~0.4 s). Awaitable. Ignored while a round is already loading.
func start_round(difficulty_index: int) -> void:
	if _loading:
		return
	# Validate first: once _loading is set only the end of this coroutine clears it.
	if difficulty_index < 0 or difficulty_index >= difficulty_files.size():
		push_error("RoundManager: no difficulty %d" % difficulty_index)
		return
	var cfg := load(difficulty_files[difficulty_index]) as DifficultyConfig
	if cfg == null or cfg.pile_count > pile_anchors.size():
		push_error("RoundManager: bad difficulty config or too few pile anchors for %s" % difficulty_files[difficulty_index])
		return
	_loading = true
	_running = false
	EventBus.loading_changed.emit(true) # listeners drop references to the old piles
	await get_tree().process_frame # let the overlay reach the screen before the heavy work
	for pile in piles:
		pile.queue_free()
	piles.clear()
	_config = cfg
	data = ChallengeGenerator.new(_config).generate(_rng)
	await get_tree().process_frame
	for k in _config.pile_count:
		var pile := ObjectPile.new()
		pile.position = pile_anchors[k]
		add_child(pile)
		pile.build(data, k, _rng)
		piles.append(pile)
		await get_tree().process_frame
	_elapsed = 0.0
	_running = true
	_loading = false
	EventBus.loading_changed.emit(false)
	EventBus.round_started.emit(data)


func _on_object_submitted(object_id: int) -> void:
	if not _running:
		return
	if object_id == data.target_index:
		_running = false
		var bonus: int = int(maxf(0.0, _config.par_time - _elapsed) * _config.bonus_per_second)
		var payout: int = _config.base_payout + bonus
		Economy.add_money(payout)
		EventBus.submission_result.emit(true)
		EventBus.round_finished.emit(payout, _elapsed)
	else:
		_elapsed += _config.wrong_penalty_seconds
		EventBus.hud_message.emit("%s  (+%ds)" % [data.wrong_message(object_id, _config.show_wrong_property), int(_config.wrong_penalty_seconds)], false)
		EventBus.submission_result.emit(false)
