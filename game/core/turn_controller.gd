extends Node
class_name TurnController

signal state_changed

@export var state: GameState

var rng := RandomNumberGenerator.new()

# Undo stack for ACTION PHASE only
var action_stack: Array[Command] = []

# We store roll-phase snapshots *only for restoring hold flags & rerolls*, not roll outcomes.
# Roll outcomes are irreversible.
var roll_phase_snapshot := {
	"rerolls": 2,
	"held": [],
	"phase": GameState.Phase.ROLL,
	"roll_boundary_id": 0
}

func _ready():
	rng.randomize()
	if state == null:
		state = GameState.new()

func start_encounter(enemies: Array[Enemy]) -> void:
	state.enemies = enemies
	state.hero_block = 0
	state.rerolls_remaining = 2
	state.phase = GameState.Phase.ROLL
	action_stack.clear()
	_roll_all()
	_roll_enemy_intents()
	for d in state.dice:
		d.spent_this_turn = false
	_checkpoint_roll_phase()
	emit_signal("state_changed")

func _roll_all() -> void:
	for d in state.dice:
		d.held = false
		d.roll(rng)
	state.roll_boundary_id += 1

func toggle_hold(die_index: int) -> void:
	if state.phase != GameState.Phase.ROLL:
		return

	var d := state.dice[die_index]

	# Only auto-enter action phase when this click changes unheld -> held AND
	# after the change, all dice are held (and rerolls remain > 0 by definition here).
	var was_held := d.held
	d.held = not d.held

	# If you just held the final unheld die, auto-enter action phase.
	if not was_held and d.held and _all_dice_held():
		_enter_action_phase()
		return

	emit_signal("state_changed")

func _all_dice_held() -> bool:
	for die in state.dice:
		if not die.held:
			return false
	return true

func reroll_unheld() -> void:
	if state.phase != GameState.Phase.ROLL:
		return
	if state.rerolls_remaining <= 0:
		return

	for d in state.dice:
		if not d.held:
			d.roll(rng)

	state.rerolls_remaining -= 1
	state.roll_boundary_id += 1

	# Reroll is an irreversible boundary; update roll snapshot after reroll.
	_checkpoint_roll_phase()

	# If this reroll consumed the last reroll, auto-enter action phase.
	if state.rerolls_remaining == 0:
		_enter_action_phase()
		return

	emit_signal("state_changed")


func _enter_action_phase() -> void:
	if state.phase == GameState.Phase.ACTION:
		return
	state.phase = GameState.Phase.ACTION
	action_stack.clear()
	emit_signal("state_changed")


func resolve_die(die_index: int, target_id: int) -> void:
	if state.phase != GameState.Phase.ACTION:
		return
	var d := state.dice[die_index]
	if d.spent_this_turn:
		return
	if d.current_face().kind == Face.Kind.BLANK:
		return


	# Validate target if needed
	var face := d.current_face()
	if face.kind == Face.Kind.ATTACK:
		if not _is_target_valid(face, target_id):
			return

	var cmd := ResolveDieCommand.new(die_index, target_id)
	cmd.apply(state)
	action_stack.append(cmd)
	state.dice[die_index].spent_this_turn = true
	emit_signal("state_changed")

func _is_target_valid(face: Face, target_id: int) -> bool:
	var tgt := state.get_enemy_by_id(target_id)
	if tgt == null or not tgt.is_alive():
		return false
	if tgt.row == Enemy.Row.BACK and state.any_front_alive():
		return face.has_mod(Modifiers.Mod.RANGED)
	return true

func undo() -> void:
	# Only meaningful during ACTION phase
	if state.phase != GameState.Phase.ACTION:
		return

	# 1) Undo last action if any
	if action_stack.size() > 0:
		var cmd: Command = action_stack.pop_back() as Command
		cmd.revert(state)
		emit_signal("state_changed")
		return

	# 2) No actions left: return to ROLL only if rerolls remain
	if state.rerolls_remaining > 0:
		state.phase = GameState.Phase.ROLL
		emit_signal("state_changed")
		return

	# 3) Otherwise do nothing (no actions to undo and no rerolls left)
	return


func _checkpoint_roll_phase() -> void:
	roll_phase_snapshot["rerolls"] = state.rerolls_remaining
	roll_phase_snapshot["phase"] = state.phase
	roll_phase_snapshot["roll_boundary_id"] = state.roll_boundary_id

	var held_arr: Array[bool] = []
	for d in state.dice:
		held_arr.append(d.held)
	roll_phase_snapshot["held"] = held_arr

func end_turn() -> void:
	if state.phase != GameState.Phase.ACTION:
		return

	state.phase = GameState.Phase.ENEMY
	
	for e in state.enemies:
		e.block = 0
		
	for e in state.enemies:
		if not e.is_alive():
			continue
		if e.die == null:
			continue

		var cmd := ResolveDieCommand.for_enemy(e.id)
		cmd.apply(state)

	_start_new_turn()
	emit_signal("state_changed")

func _resolve_enemy_face(e: Enemy) -> void:
	var f := e.die.current_face()

	match f.kind:
		Face.Kind.ATTACK:
			_apply_damage_to_hero(f.value)
		Face.Kind.BLOCK:
			# Optional: enemy block later; for now ignore or store on enemy
			pass
		Face.Kind.BLANK:
			pass


func _apply_damage_to_hero(amount: int) -> void:
	if amount <= 0:
		return

	var absorbed := min(state.hero_block, amount)
	state.hero_block -= absorbed
	amount -= absorbed

	if amount > 0:
		state.hero_hp = max(0, state.hero_hp - amount)


func _start_new_turn() -> void:
	# Reset per-turn resources
	state.hero_block = 0
	state.rerolls_remaining = 2
	state.phase = GameState.Phase.ROLL

	for d in state.dice:
		d.spent_this_turn = false

	# Clear holds and roll fresh
	for d in state.dice:
		d.held = false
		d.roll(rng)
	_roll_enemy_intents()

	# Irreversible roll boundary
	state.roll_boundary_id += 1

	# Refresh roll snapshot (so undo can't "rewind" past this boundary)
	_checkpoint_roll_phase()

	# Clear action stack at turn boundary
	action_stack.clear()

func _roll_enemy_intents() -> void:
	for e in state.enemies:
		if not e.is_alive():
			continue
		if e.die == null:
			continue
		e.die.roll(rng)


func has_unspent_nonblank_faces() -> bool:
	for d in state.dice:
		if d.spent_this_turn:
			continue
		if d.current_face().kind != Face.Kind.BLANK:
			return true
	return false
