extends Node
## Dev-only visual probe (not CI): boots the real game scene, drives scripted
## input through the normal Input singleton (action presses + mouse warp), and
## saves periodic screenshots for look-and-feel review without playing. Audio
## is muted. The sim path is untouched — input enters exactly like a player's.
##
##   godot --path . res://tests/visual_probe.tscn ++ --out /abs/dir --seconds 45

var _main: Node2D = null
var _frames: int = 0
var _shots: int = 0
var _out_dir: String = "user://probe"
var _run_frames: int = 45 * 60
## Screenshot cadence in view frames.
var _shot_interval: int = 90
## Frames until the next allowed reset tap (death panel / Between advance).
var _reset_hold: int = 0

## Save files the game writes during a session, snapshotted at probe start and
## restored on exit so probe runs never pollute real progress.
const SAVE_FILES: Array[String] = [
	"user://active_slot.json", "user://save.json",
	"user://save_slot_1.json", "user://save_slot_2.json", "user://save_slot_3.json",
]
## path -> original contents (String), or null if the file didn't exist.
var _save_backup: Dictionary = {}


func _snapshot_saves() -> void:
	for f: String in SAVE_FILES:
		if FileAccess.file_exists(f):
			_save_backup[f] = FileAccess.get_file_as_string(f)
		else:
			_save_backup[f] = null


func _restore_saves() -> void:
	for f: String in SAVE_FILES:
		var original: Variant = _save_backup.get(f)
		if original == null:
			if FileAccess.file_exists(f):
				DirAccess.remove_absolute(ProjectSettings.globalize_path(f))
		else:
			var out := FileAccess.open(f, FileAccess.WRITE)
			if out != null:
				out.store_string(String(original))


func _exit_tree() -> void:
	_restore_saves()


## Give the probe session every schematic so gear verbs (mines) are visible
## in screenshots. Runs after the snapshot; the restore undoes it.
func _doctor_save() -> void:
	var slot := 1
	if FileAccess.file_exists("user://active_slot.json"):
		var parsed: Variant = JSON.parse_string(
			FileAccess.get_file_as_string("user://active_slot.json"))
		if parsed is Dictionary:
			slot = clampi(int(parsed.get("slot", 1)), 1, 3)
	var path := "user://save_slot_%d.json" % slot
	var save: Dictionary = {}
	if FileAccess.file_exists(path):
		var parsed_save: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed_save is Dictionary:
			save = parsed_save
	save["schematics"] = ["mine_dispenser"]
	var out := FileAccess.open(path, FileAccess.WRITE)
	if out != null:
		out.store_string(JSON.stringify(save))


func _ready() -> void:
	_snapshot_saves()
	_doctor_save()
	var args := OS.get_cmdline_user_args()
	for i in args.size():
		if args[i] == "--out" and i + 1 < args.size():
			_out_dir = args[i + 1]
		elif args[i] == "--seconds" and i + 1 < args.size():
			_run_frames = int(args[i + 1]) * 60
		elif args[i] == "--interval" and i + 1 < args.size():
			_shot_interval = maxi(int(args[i + 1]), 1)
	if _out_dir.begins_with("user://"):
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(_out_dir))
	else:
		DirAccess.make_dir_recursive_absolute(_out_dir)

	AudioServer.set_bus_mute(0, true)
	_main = load("res://view/main.tscn").instantiate()
	add_child(_main)
	# Force 1:1 window <-> viewport so mouse warp coordinates equal world
	# coordinates (overrides any saved display preset the machine has).
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(1280, 720)


func _physics_process(_delta: float) -> void:
	_frames += 1
	_drive_input()
	if _frames % _shot_interval == 0:
		_screenshot()
	if _frames >= _run_frames:
		_release_all()
		get_tree().quit()


func _drive_input() -> void:
	var core: Variant = _main.get("_core")
	if core == null:
		return
	var state: Variant = core.state
	var mode: int = _main.get("_mode")

	# Death panel or the Between: linger long enough to screenshot it, then
	# tap reset to advance (the Between also accepts reset to redeploy).
	if state.player_down or mode != 0:
		_release_all()
		if _reset_hold > 0:
			_reset_hold -= 1
			Input.action_release("reset")
			return
		Input.action_press("reset")
		_reset_hold = 130
		return
	Input.action_release("reset")

	Input.action_press("fire")

	# Wander: strafe left/right with occasional vertical drift, biased to
	# stay in the lower half where the player spawns.
	for a: String in ["move_left", "move_right", "move_up", "move_down"]:
		Input.action_release(a)
	match (_frames / 70) % 6:
		0, 3:
			Input.action_press("move_left")
		1, 4:
			Input.action_press("move_right")
		2:
			Input.action_press("move_up")
		5:
			Input.action_press("move_down")

	if _frames % 200 == 0:
		Input.action_press("dodge")
	else:
		Input.action_release("dodge")

	# Periodically hold the breath so screenshots exercise the slow + meter.
	if (_frames % 900) > 620:
		Input.action_press("focus")
	else:
		Input.action_release("focus")

	# Drop a mine now and then (needs the doctored schematic + stock).
	if _frames % 300 == 0:
		Input.action_press("mine")
	else:
		Input.action_release("mine")

	# Aim at the nearest enemy via mouse warp. World -> screen through the
	# canvas transform (the camera scrolls now), clamped into the window.
	var best: Vector2 = state.player_pos + Vector2(0.0, -200.0)
	var best_d := INF
	for e: Variant in state.enemies:
		var d: float = e.pos.distance_squared_to(state.player_pos)
		if d < best_d:
			best_d = d
			best = e.pos
	var screen: Vector2 = _main.get_viewport().get_canvas_transform() * best
	screen.x = clampf(screen.x, 8.0, 1272.0)
	screen.y = clampf(screen.y, 8.0, 712.0)
	Input.warp_mouse(screen)


func _release_all() -> void:
	for a: String in [
		"fire", "dodge", "reset", "focus", "mine",
		"move_left", "move_right", "move_up", "move_down",
	]:
		Input.action_release(a)


func _screenshot() -> void:
	var img := get_viewport().get_texture().get_image()
	_shots += 1
	var path := _out_dir.path_join("probe_%03d.png" % _shots)
	if path.begins_with("user://"):
		path = ProjectSettings.globalize_path(path)
	img.save_png(path)
