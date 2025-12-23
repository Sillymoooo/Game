extends Resource
class_name GameState

enum Phase {
	ROLL,
	ACTION,
	ENEMY
}

@export var hero_hp: int = 30
@export var hero_max_hp: int = 30
@export var hero_block: int = 0

@export var rerolls_remaining: int = 2
@export var phase: Phase = Phase.ROLL

@export var dice: Array[Die] = []
@export var enemies: Array[Enemy] = []

# Non-undoable boundary tracking
var roll_boundary_id: int = 0

func _init():
	if dice.is_empty():
		for i in range(5):
			dice.append(Die.new())

func any_front_alive() -> bool:
	for e in enemies:
		if e.is_alive() and e.row == Enemy.Row.FRONT:
			return true
	return false

func alive_enemies_in_row(row: int) -> Array[Enemy]:
	var out: Array[Enemy] = []
	for e in enemies:
		if e.is_alive() and e.row == row:
			out.append(e)
	return out

func get_enemy_by_id(enemy_id: int) -> Enemy:
	for e in enemies:
		if e.id == enemy_id:
			return e
	return null
