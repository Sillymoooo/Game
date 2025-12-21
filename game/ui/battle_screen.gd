extends Control

@onready var menu_button: Button = $RootVBox/TopBar/TopBarHBox/MenuButton
@onready var back_row_hbox: HBoxContainer = $RootVBox/Arena/ArenaVBox/BackRowHBox
@onready var front_row_hbox: HBoxContainer = $RootVBox/Arena/ArenaVBox/FrontRowHBox
@onready var tooltip_title: Label = $RootVBox/Cockpit/CockpitHBox/TooltipVBox/TooltipTitle
@onready var tooltip_body: Label = $RootVBox/Cockpit/CockpitHBox/TooltipVBox/TooltipBody
@onready var dice_hbox: HBoxContainer = $RootVBox/Cockpit/CockpitHBox/MiddleVBox/DiceHBox
@onready var rerolls_label: Label = $RootVBox/Cockpit/CockpitHBox/ButtonsVBox/RerollsLabel
@onready var phase_label: Label = $RootVBox/Cockpit/CockpitHBox/ButtonsVBox/PhaseLabel
@onready var reroll_button: Button = $RootVBox/Cockpit/CockpitHBox/ButtonsVBox/RerollButton
@onready var phase_button: Button = $RootVBox/Cockpit/CockpitHBox/ButtonsVBox/PhaseButton
@onready var undo_button: Button = $RootVBox/Cockpit/CockpitHBox/ButtonsVBox/UndoButton
@onready var turn: TurnController = get_node_or_null("TurnController") as TurnController
@onready var hp_label: Label = $RootVBox/Cockpit/CockpitHBox/MiddleVBox/StatusPanel/CombatStatusHBox/HpLabel
@onready var block_label: Label = $RootVBox/Cockpit/CockpitHBox/MiddleVBox/StatusPanel/CombatStatusHBox/BlockLabel
@onready var end_turn_confirm: ConfirmationDialog = $EndTurnConfirm

@export var test_enemies: Array[EnemyArchetype] = []

var pending_attack_die_index: int = -1

func _ready() -> void:
	if turn == null:
		push_error("No TurnController node found at BattleScreen/TurnController")
		return
	
	var k := OS.get_environment("api_key")
	print("OPENAI_API_KEY present?", k.length() > 0, "len=", k.length())

	
	# Hook buttons
	reroll_button.pressed.connect(_on_reroll_pressed)
	phase_button.pressed.connect(_on_phase_pressed)
	undo_button.pressed.connect(_on_undo_pressed)

	# Temporary tooltip defaults
	tooltip_title.text = "Ready"
	tooltip_body.text = "Roll, hold, reroll. Then act."

	turn.state_changed.connect(_refresh)
	turn.start_encounter(_make_test_enemies())
	
	end_turn_confirm.confirmed.connect(_on_end_turn_confirmed)
	
	_refresh()



func _make_test_enemies() -> Array[Enemy]:
	var enemies: Array[Enemy] = []
	var id := 1
	for a in test_enemies:
		enemies.append(a.instantiate(id))
		id += 1
	return enemies

func _refresh() -> void:
	_build_enemy_rows()
	_build_dice_strip()
	_update_controls()
	_update_status()

func _build_enemy_rows() -> void:
	# Clear
	for c in back_row_hbox.get_children():
		c.queue_free()
	for c in front_row_hbox.get_children():
		c.queue_free()

	# Populate from turn.state.enemies
	if turn.state == null:
		return

	var front_alive := turn.state.any_front_alive()

	for e in turn.state.enemies:
		var b := Button.new()
		var intent := ""
		if e.die != null:
			var ef := e.die.current_face()
			match ef.kind:
				Face.Kind.ATTACK: intent = "ATK %d" % ef.value
				Face.Kind.BLOCK: intent = "BLK %d" % ef.value
				Face.Kind.BLANK: intent = "—"

		b.text = "%s (%d/%d)  Blk %d  %s" % [e.name, e.hp, e.max_hp, e.block, intent]

		var can_target := e.is_alive()

		if can_target and turn.state.phase == GameState.Phase.ACTION and pending_attack_die_index >= 0:
			var d := turn.state.dice[pending_attack_die_index]
			var face := d.current_face()

			if e.row == Enemy.Row.BACK and front_alive and not face.has_mod(Modifiers.Mod.RANGED):
				can_target = false

		b.disabled = not can_target
		b.modulate.a = 1.0 if can_target else 0.35

		b.pressed.connect(func():
			_on_enemy_pressed(e.id)
		)

		if e.row == Enemy.Row.BACK:
			back_row_hbox.add_child(b)
		else:
			front_row_hbox.add_child(b)


func _build_dice_strip() -> void:
	for c in dice_hbox.get_children():
		c.queue_free()

	if turn.state == null:
		return

	for i in range(turn.state.dice.size()):
		var d := turn.state.dice[i]
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		if turn.state.phase == GameState.Phase.ROLL:
			b.toggle_mode = true
			b.button_pressed = d.held
		else:
			b.toggle_mode = false
			b.button_pressed = false
		b.text = _die_text(d)

		if turn.state.phase == GameState.Phase.ACTION:
			if d.spent_this_turn or d.current_face().kind == Face.Kind.BLANK:
				b.disabled = true
				b.modulate.a = 0.35
			else:
				b.toggle_mode = false
				b.button_pressed = false
	
		b.pressed.connect(func():
			_on_die_pressed(i)
		)

		dice_hbox.add_child(b)

func _die_text(d: Die) -> String:
	var f := d.current_face()
	var t := ""
	match f.kind:
		Face.Kind.ATTACK: t = "ATK %d" % f.value
		Face.Kind.BLOCK: t = "BLK %d" % f.value
		Face.Kind.BLANK: t = "BLANK"
	return ("%s (H)" % t) if d.held else t


func _update_controls() -> void:
	if turn.state == null:
		return

	# Reroll only in roll phase and if rerolls remain
	reroll_button.disabled = not (turn.state.phase == GameState.Phase.ROLL and turn.state.rerolls_remaining > 0)

	# Phase button changes meaning
	if turn.state.phase == GameState.Phase.ROLL:
		phase_button.text = "End Turn"
		phase_button.disabled = true
	elif turn.state.phase == GameState.Phase.ACTION:
		phase_button.text = "End Turn"
		phase_button.disabled = false
	else:
		phase_button.text = "..."
		phase_button.disabled = true

	# Undo only in action phase (per your spec)
	undo_button.disabled = not (turn.state.phase == GameState.Phase.ACTION and (turn.action_stack.size() > 0 or turn.state.rerolls_remaining > 0))

func _update_status() -> void:
	if turn.state == null:
		hp_label.text = ""
		block_label.text = ""
		rerolls_label.text = ""
		phase_label.text = ""
		return

	hp_label.text = "HP %d/%d" % [turn.state.hero_hp, turn.state.hero_max_hp]
	block_label.text = "Block %d" % turn.state.hero_block
	rerolls_label.text = "Rerolls %d" % turn.state.rerolls_remaining
	phase_label.text = _phase_name(turn.state.phase)

func _phase_name(p: int) -> String:
	match p:
		GameState.Phase.ROLL: return "ROLL"
		GameState.Phase.ACTION: return "ACTION"
		GameState.Phase.ENEMY: return "ENEMY"
	return "?"

func _on_die_pressed(i: int) -> void:
	if turn.state.phase == GameState.Phase.ROLL:
		turn.toggle_hold(i)
		return

	if turn.state.phase != GameState.Phase.ACTION:
		return

	var d := turn.state.dice[i]

	if d.spent_this_turn:
		return

	var f := d.current_face()
	if turn.state.phase == GameState.Phase.ACTION and f.kind == Face.Kind.BLANK:
		return

	if f.kind == Face.Kind.ATTACK:
		pending_attack_die_index = i
		tooltip_title.text = "Select a target"
		tooltip_body.text = "Die %d: %s" % [i + 1, _die_text(d)]
		_refresh()
		return

	# Block/blank resolve immediately
	turn.resolve_die(i, -1)

func _on_enemy_pressed(enemy_id: int) -> void:
	if turn.state.phase != GameState.Phase.ACTION:
		return
	if pending_attack_die_index < 0:
		return

	turn.resolve_die(pending_attack_die_index, enemy_id)
	pending_attack_die_index = -1
	tooltip_title.text = "Action"
	tooltip_body.text = "Resolved."
	_refresh()

func _on_reroll_pressed() -> void:
	turn.reroll_unheld()

func _on_phase_pressed() -> void:
	if turn.state == null:
		return

	if turn.state.phase == GameState.Phase.ACTION:
		# If there are still usable faces, ask for confirmation.
		if turn.has_unspent_nonblank_faces():
			end_turn_confirm.dialog_text = "You still have unused actions. End turn anyway?"
			end_turn_confirm.popup_centered()
			return

		# Otherwise end immediately
		_on_end_turn_confirmed()


func _on_undo_pressed() -> void:
	turn.undo()
	pending_attack_die_index = -1
	tooltip_title.text = "Undo"
	tooltip_body.text = "Reverted last action."

func _on_end_turn_confirmed() -> void:
	pending_attack_die_index = -1
	turn.end_turn()
