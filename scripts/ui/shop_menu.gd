extends CanvasLayer
## Buy menu (pauses the game while open) plus the "press B" prompt shown near a terminal.

@export var item_id: StringName = &"small_magnet"
@export var item_name: String = "Small Magnet"
@export var item_price: int = 50

var _owned: bool = false
var _near: bool = false
var _open: bool = false

@onready var _prompt: Label = $Prompt
@onready var _dim: Control = $Dim
@onready var _panel: Control = $Panel
@onready var _balance: Label = $Panel/Margin/VBox/Balance
@onready var _item_label: Label = $Panel/Margin/VBox/ItemRow/ItemLabel
@onready var _buy: Button = $Panel/Margin/VBox/ItemRow/BuyButton


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_item_label.text = "%s  -  $%d" % [item_name, item_price]
	EventBus.shop_prompt_changed.connect(func(near: bool) -> void:
		_near = near
		_refresh())
	EventBus.shop_requested.connect(_set_open.bind(true))
	Economy.money_changed.connect(func(_t: int, _a: int, _p: Vector3) -> void: _refresh())
	Economy.money_spent.connect(func(_a: int, _t: int) -> void: _refresh())
	_buy.pressed.connect(_on_buy_pressed)
	_set_open(false)


func _unhandled_input(event: InputEvent) -> void:
	if _open and (event.is_action_pressed("open_shop") or event.is_action_pressed("ui_cancel")):
		get_viewport().set_input_as_handled()
		_set_open(false)


func _set_open(open: bool) -> void:
	_open = open
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else Input.MOUSE_MODE_CAPTURED
	_refresh()


func _on_buy_pressed() -> void:
	if _owned or not Economy.try_spend(item_price):
		return
	_owned = true
	EventBus.item_purchased.emit(item_id)
	_refresh()


func _refresh() -> void:
	_dim.visible = _open
	_panel.visible = _open
	_prompt.visible = _near and not _open
	_balance.text = "Balance: $%d" % Economy.money
	_buy.disabled = _owned or Economy.money < item_price
	_buy.text = "Owned" if _owned else "Buy"
