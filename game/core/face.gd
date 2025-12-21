extends Resource
class_name Face

enum Kind {
	ATTACK,
	BLOCK,
	BLANK
}

@export var kind: Kind = Kind.BLANK
@export var value: int = 0
@export var mods: Array[int] = [] # store Modifiers.Mod values

func is_blank() -> bool:
	return kind == Kind.BLANK

func has_mod(m: int) -> bool:
	return mods.has(m)

static func attack(v: int, mods_in: Array[int] = []) -> Face:
	var f := Face.new()
	f.kind = Kind.ATTACK
	f.value = v
	f.mods = mods_in.duplicate()
	return f

static func block(v: int, mods_in: Array[int] = []) -> Face:
	var f := Face.new()
	f.kind = Kind.BLOCK
	f.value = v
	f.mods = mods_in.duplicate()
	return f

static func blank() -> Face:
	var f := Face.new()
	f.kind = Kind.BLANK
	f.value = 0
	f.mods = []
	return f
