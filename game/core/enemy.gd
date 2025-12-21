extends Resource
class_name Enemy

enum Row {
	FRONT,
	BACK
}

@export var id: int = 0
@export var name: String = "Enemy"
@export var row: Row = Row.FRONT
@export var hp: int = 10
@export var max_hp: int = 10
@export var block: int = 0

@export var die: Die = null
var rolled_this_phase: bool = false

func is_alive() -> bool:
	return hp > 0
