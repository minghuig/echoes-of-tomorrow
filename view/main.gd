extends Node2D
## View root: owns the SimCore, translates raw input into one Command per
## physics tick, and derives all feedback (shake, hit-stop, zoom punch,
## particles) by diffing successive SimStates — the sim emits no events and
## stays pure. Feel state here never feeds back into game logic.

const SimCoreScript := preload("res://sim/sim_core.gd")
const SimStateScript := preload("res://sim/sim_state.gd")
const SimCommand := preload("res://sim/command.gd")
const BackgroundScript := preload("res://view/background.gd")
const WorldScript := preload("res://view/world_renderer.gd")
const FxScript := preload("res://view/fx.gd")
const OverlayScript := preload("res://view/overlay.gd")

const RUN_SEED: int = 7
const STICK_AIM_DEADZONE: float = 0.35

const TRAIL_LENGTH: int = 9
const SHAKE_MAX_OFFSET: float = 13.0
const TRAUMA_DECAY: float = 2.4
const RECOIL_KICK: float = 3.5
const RECOIL_DECAY: float = 12.0
const PUNCH_DECAY: float = 9.0
const AFTERIMAGE_MIN_SPEED: float = 240.0
const THRUST_MIN_SPEED: float = 90.0

var _core: SimCoreScript
var _view_rng := RandomNumberGenerator.new()

# View-only feel state.
var _hitstop_ticks: int = 0
var _trauma: float = 0.0
var _punch: float = 0.0
var _recoil := Vector2.ZERO

# Interpolation + trail bookkeeping, keyed by projectile instance id.
# The dictionaries are shared by reference with the world renderer.
var _prev_player_pos := Vector2.ZERO
var _proj_prev: Dictionary[int, Vector2] = {}
var _proj_trails: Dictionary[int, PackedVector2Array] = {}

@onready var _background: BackgroundScript = $Background
@onready var _world: WorldScript = $World
@onready var _fx: FxScript = $Effects
@onready var _overlay: OverlayScript = $OverlayLayer/Overlay


func _ready() -> void:
	_view_rng.randomize()
	_core = SimCoreScript.new()
	_core.setup(RUN_SEED)
	_prev_player_pos = _core.state.player_pos

	_background.arena_size = _core.state.arena_size
	_world.core = _core
	_world.prev_player_pos = _prev_player_pos
	_world.proj_prev = _proj_prev
	_world.proj_trails = _proj_trails
	_overlay.core = _core
	_overlay.total_targets = _core.state.blocks.size()


func _physics_process(_delta: float) -> void:
	var state: SimStateScript = _core.state

	if _hitstop_ticks > 0:
		_hitstop_ticks -= 1
		_snap_interpolation(state)
		return

	# Snapshot the bits of state we diff for feedback after the step.
	var pre_blocks: Array[SimStateScript.Block] = state.blocks.duplicate()
	var pre_hp: Array[int] = []
	for b: SimStateScript.Block in pre_blocks:
		pre_hp.append(b.hp)
	var pre_projectiles: Array[SimStateScript.Projectile] = state.projectiles.duplicate()
	var pre_dodge_cd := state.dodge_cooldown
	_prev_player_pos = state.player_pos
	_world.prev_player_pos = _prev_player_pos
	for p: SimStateScript.Projectile in state.projectiles:
		_proj_prev[p.get_instance_id()] = p.pos

	_core.step(_build_command())

	_diff_blocks(state, pre_blocks, pre_hp)
	_diff_projectiles(state, pre_projectiles)
	_emit_player_feedback(state, pre_dodge_cd)
	_update_trails(state)


func _process(delta: float) -> void:
	_trauma = maxf(_trauma - TRAUMA_DECAY * delta, 0.0)
	_punch *= exp(-PUNCH_DECAY * delta)
	_recoil *= exp(-RECOIL_DECAY * delta)
	_world.recoil = _recoil

	# Shake offsets the whole world (the overlay lives on a CanvasLayer and
	# stays put); the punch is a tiny zoom kept centered on the arena.
	var shake := Vector2.ZERO
	if _trauma > 0.0:
		var amp := _trauma * _trauma * SHAKE_MAX_OFFSET
		shake = Vector2(
			_view_rng.randf_range(-amp, amp), _view_rng.randf_range(-amp, amp))
	var zoom := 1.0 + _punch
	scale = Vector2(zoom, zoom)
	position = _core.state.arena_size * 0.5 * (1.0 - zoom) + shake


## Translate raw input into this tick's Command (the only path into the sim).
func _build_command() -> SimCommand:
	var cmd := SimCommand.new()
	cmd.move = Input.get_vector("move_left", "move_right", "move_up", "move_down")
	cmd.aim = _read_aim()
	cmd.fire = Input.is_action_pressed("fire")
	cmd.dodge = Input.is_action_just_pressed("dodge")
	return cmd


func _read_aim() -> Vector2:
	var stick := Vector2(
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_X),
		Input.get_joy_axis(0, JOY_AXIS_RIGHT_Y),
	)
	if stick.length() > STICK_AIM_DEADZONE:
		return stick.normalized()
	return get_global_mouse_position() - _core.state.player_pos


func _diff_blocks(
	state: SimStateScript,
	pre_blocks: Array[SimStateScript.Block],
	pre_hp: Array[int],
) -> void:
	for i in pre_blocks.size():
		var b := pre_blocks[i]
		if b.hp <= 0:
			# Destroyed this tick (sim decrements in place, then filters).
			_fx.block_destroyed(Rect2(b.pos, b.size))
			_add_trauma(0.4)
			_punch = maxf(_punch, 0.025)
			_hitstop_ticks = maxi(_hitstop_ticks, 4)
			if state.blocks.is_empty():
				_hitstop_ticks = 10
				_add_trauma(0.6)
				_punch = 0.05
		elif b.hp < pre_hp[i]:
			_fx.block_hit(Rect2(b.pos, b.size))
			_add_trauma(0.16)


func _diff_projectiles(
	state: SimStateScript, pre_projectiles: Array[SimStateScript.Projectile]
) -> void:
	var cur_ids: Dictionary[int, bool] = {}
	for p: SimStateScript.Projectile in state.projectiles:
		cur_ids[p.get_instance_id()] = true

	# New projectile => the player fired this tick.
	for p: SimStateScript.Projectile in state.projectiles:
		var id := p.get_instance_id()
		if _proj_prev.has(id):
			continue
		var dir := p.vel.normalized()
		# The sim already advanced the new projectile once; back up to the muzzle.
		var muzzle := p.pos - p.vel * SimCoreScript.DT
		_proj_prev[id] = muzzle
		_fx.muzzle_flash(muzzle, dir)
		_recoil = -dir * RECOIL_KICK
		_add_trauma(0.07)

	# Removed projectile => impact (or quiet fizzle at end of life).
	var margin := _core.projectile_radius + 2.0
	for p: SimStateScript.Projectile in pre_projectiles:
		var id := p.get_instance_id()
		if cur_ids.has(id):
			continue
		var inside := (
			p.pos.x > margin and p.pos.y > margin
			and p.pos.x < state.arena_size.x - margin
			and p.pos.y < state.arena_size.y - margin
		)
		if inside and p.ttl > 0:
			_fx.impact(p.pos, -p.vel.normalized())
			_add_trauma(0.10)
		elif inside:
			_fx.fizzle(p.pos)
		var trail: PackedVector2Array = _proj_trails.get(id, PackedVector2Array())
		if trail.size() >= 2:
			_fx.trail_ghost(trail)
		_proj_trails.erase(id)
		_proj_prev.erase(id)


func _emit_player_feedback(state: SimStateScript, pre_dodge_cd: int) -> void:
	if state.dodge_cooldown > pre_dodge_cd and state.dodge_vel != Vector2.ZERO:
		_fx.dodge_burst(state.player_pos, state.dodge_vel.normalized())
		_add_trauma(0.12)

	if state.dodge_vel.length() > AFTERIMAGE_MIN_SPEED:
		_fx.afterimage(
			state.player_pos,
			state.player_aim.angle() + PI / 2.0,
			_core.player_radius,
			_core.player_radius * 0.45,
		)

	if state.player_vel.length() > THRUST_MIN_SPEED and state.tick % 2 == 0:
		var back := -state.player_vel.normalized()
		_fx.thrust(
			state.player_pos + back * (_core.player_radius + 2.0),
			state.player_vel * -0.12,
		)


func _update_trails(state: SimStateScript) -> void:
	for p: SimStateScript.Projectile in state.projectiles:
		var id := p.get_instance_id()
		var trail: PackedVector2Array = _proj_trails.get(id, PackedVector2Array())
		trail.append(p.pos)
		if trail.size() > TRAIL_LENGTH:
			trail = trail.slice(trail.size() - TRAIL_LENGTH)
		_proj_trails[id] = trail


## During hit-stop nothing moves, so pin interpolation sources to the current
## positions — otherwise the renderer would replay the last tick's motion.
func _snap_interpolation(state: SimStateScript) -> void:
	_prev_player_pos = state.player_pos
	_world.prev_player_pos = _prev_player_pos
	for p: SimStateScript.Projectile in state.projectiles:
		_proj_prev[p.get_instance_id()] = p.pos


func _add_trauma(amount: float) -> void:
	_trauma = minf(_trauma + amount, 1.0)
