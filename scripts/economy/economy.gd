extends Node
## Autoload: owns the money total.

signal money_changed(total: int, amount: int, world_position: Vector3)

var money: int = 0


func add_money(amount: int, world_position: Vector3 = Vector3.ZERO) -> void:
	money += amount
	money_changed.emit(money, amount, world_position)
