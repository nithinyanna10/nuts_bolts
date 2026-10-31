extends Node
## Autoload: owns the money total.

signal money_changed(total: int, amount: int, world_position: Vector3)

signal money_spent(amount: int, total: int)

var money: int = 0


func add_money(amount: int, world_position: Vector3 = Vector3.ZERO) -> void:
	money += amount
	money_changed.emit(money, amount, world_position)


## Returns false (and changes nothing) if the player can't afford it.
func try_spend(amount: int) -> bool:
	if amount > money:
		return false
	money -= amount
	money_spent.emit(amount, money)
	return true
