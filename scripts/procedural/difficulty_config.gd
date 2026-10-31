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
@export var pile_layers: float = 3.0 ## average stack depth; sets the pile radius
@export var pile_spread: float = 1.0
@export var grid_cell_size: float = 0.5
