extends Resource
class_name Die

# Each die has 3 pairs => 6 faces
# A pair can be:
# - Double pair: two standard faces
# - Half-filled: one double-strength face + blank
# We model this simply as 6 face definitions; upgrades later will operate at the pair index.

@export var spent_this_turn: bool = false

@export var faces: Array[Face] = [] # length 6
var rolled_index: int = -1
var held: bool = false

func _init():
	if faces.is_empty():
		# Example starter: one double pair Attack1/Attack1, and two empty pairs (blanks)
		faces = [
			Face.attack(1), Face.attack(1),
			Face.blank(), Face.blank(),
			Face.blank(), Face.blank()
		]

func roll(rng: RandomNumberGenerator) -> void:
	rolled_index = rng.randi_range(0, faces.size() - 1)

func current_face() -> Face:
	if rolled_index < 0:
		return Face.blank()
	return faces[rolled_index]

func set_held(v: bool) -> void:
	held = v
