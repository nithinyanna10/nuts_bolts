class_name RoundManager
extends Node3D
## Starts rounds: generates the order and objects, builds the piles at their anchors.

@export_file("*.tres") var difficulty_files: Array[String] = []
@export var pile_anchors: Array[Vector3] = []
@export var start_difficulty: int = 0

var data: RoundData
var piles: Array[ObjectPile] = []
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	_rng.randomize()
	start_round(start_difficulty)


func start_round(difficulty_index: int) -> void:
	for pile in piles:
		pile.queue_free()
	piles.clear()
	var cfg: DifficultyConfig = load(difficulty_files[difficulty_index])
	data = ChallengeGenerator.new(cfg).generate(_rng)
	for k in cfg.pile_count:
		var pile := ObjectPile.new()
		pile.position = pile_anchors[k]
		add_child(pile)
		pile.build(data, k, _rng)
		piles.append(pile)
	EventBus.round_started.emit(data)
