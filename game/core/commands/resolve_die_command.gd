extends Command
class_name ResolveDieCommand

enum Owner {
	PLAYER,
	ENEMY
}

var owner: Owner = Owner.PLAYER

# Player fields
var die_index: int = -1
var target_id: int = -1 # enemy id, -1 if none

# Enemy fields
var enemy_id: int = -1

# Snapshots for undo
var prev_enemy_hp: Dictionary = {}
var prev_enemy_block: Dictionary = {}
var prev_hero_block: int = 0
var prev_hero_hp: int = 0

var prev_die_held: bool = false
var prev_die_rolled_index: int = -1
var prev_die_spent: bool = false

var prev_enemy_die_rolled_index: int = -1

func _init(die_idx: int, tgt_id: int):
	owner = Owner.PLAYER
	die_index = die_idx
	target_id = tgt_id

static func for_enemy(e_id: int) -> ResolveDieCommand:
	var cmd := ResolveDieCommand.new(-1, -1)
	cmd.owner = Owner.ENEMY
	cmd.enemy_id = e_id
	return cmd

func apply(state: GameState) -> void:
	# Snapshot shared state
	prev_hero_block = state.hero_block
	prev_hero_hp = state.hero_hp

	# Snapshot enemy HPs (player actions can change multiple via future modifiers)
	prev_enemy_hp.clear()
	for e in state.enemies:
		prev_enemy_hp[e.id] = e.hp
		prev_enemy_block[e.id] = e.block
	
	if owner == Owner.PLAYER:
		_apply_player(state)
	else:
		_apply_enemy(state)

func _apply_player(state: GameState) -> void:
	var d := state.dice[die_index]
	prev_die_held = d.held
	prev_die_rolled_index = d.rolled_index
	prev_die_spent = d.spent_this_turn

	var face := d.current_face()
	match face.kind:
		Face.Kind.ATTACK:
			_apply_attack_to_enemy(state, face)
		Face.Kind.BLOCK:
			state.hero_block += face.value
		Face.Kind.BLANK:
			pass

	# Mark die as used this turn
	d.spent_this_turn = true

	# Optional UI cue (reversible)
	d.held = false

func _apply_enemy(state: GameState) -> void:
	var e := state.get_enemy_by_id(enemy_id)
	if e == null or not e.is_alive():
		return
	if e.die == null:
		return

	# Snapshot enemy die roll index so we can undo cleanly (even if you don’t expose enemy undo today)
	prev_enemy_die_rolled_index = e.die.rolled_index

	var face := e.die.current_face()
	match face.kind:
		Face.Kind.ATTACK:
			_apply_damage_to_hero(state, face.value)
		Face.Kind.BLOCK:
			# If you later add enemy block, add e.block and snapshot it like hero_block
			pass
		Face.Kind.BLANK:
			pass

func _apply_attack_to_enemy(state: GameState, face: Face) -> void:
	if target_id < 0:
		return
	var tgt := state.get_enemy_by_id(target_id)
	if tgt == null or not tgt.is_alive():
		return

	var dmg := face.value

	# Consume enemy block first
	var absorbed := min(tgt.block, dmg)
	tgt.block -= absorbed
	dmg -= absorbed

	if dmg > 0:
		tgt.hp = max(0, tgt.hp - dmg)


func _apply_damage_to_hero(state: GameState, amount: int) -> void:
	if amount <= 0:
		return

	var absorbed := min(state.hero_block, amount)
	state.hero_block -= absorbed
	amount -= absorbed

	if amount > 0:
		state.hero_hp = max(0, state.hero_hp - amount)

func revert(state: GameState) -> void:
	state.hero_block = prev_hero_block
	state.hero_hp = prev_hero_hp

	for e in state.enemies:
		if prev_enemy_hp.has(e.id):
			e.hp = int(prev_enemy_hp[e.id])
		if prev_enemy_block.has(e.id):
			e.block = int(prev_enemy_block[e.id])

	if owner == Owner.PLAYER:
		var d := state.dice[die_index]
		d.held = prev_die_held
		d.rolled_index = prev_die_rolled_index
		d.spent_this_turn = prev_die_spent
	else:
		var e := state.get_enemy_by_id(enemy_id)
		if e != null and e.die != null:
			e.die.rolled_index = prev_enemy_die_rolled_index
