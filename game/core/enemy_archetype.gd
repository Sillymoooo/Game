extends Resource
class_name EnemyArchetype

@export var name: String = "Enemy"
@export var max_hp: int = 6
@export var row: Enemy.Row = Enemy.Row.FRONT
@export var die_faces: Array[Face] = []   # 6 faces, standard

func instantiate(id: int) -> Enemy:
	var e := Enemy.new()
	e.id = id
	e.name = name
	e.row = row
	e.hp = max_hp
	e.max_hp = max_hp

	var d := Die.new()
	d.faces = die_faces.duplicate(true) # deep copy so tweaks don't cross-contaminate
	e.die = d

	return e
