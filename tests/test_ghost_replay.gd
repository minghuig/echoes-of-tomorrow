extends SceneTree
## M3 architecture gate, headless: a recorded run must replay tick-for-tick
## through a fresh SimCore stepped in lockstep with an unrelated live run.
## Records (seed, command_log) plus checkpoint hashes from an original run,
## then re-runs the log as a ghost while a second sim with different seed
## and inputs advances beside it. Compares every checkpoint hash and the
## final serialized state byte-for-byte. Exits 0 on PASS, 1 on FAIL.
##
##   godot --headless --path . --script res://tests/test_ghost_replay.gd

const SimCoreScript := preload("res://sim/sim_core.gd")
const SimCommand := preload("res://sim/command.gd")

const RECORD_SEED: int = 4242
const LIVE_SEED: int = 9001
const TICK_COUNT: int = 600
const HASH_INTERVAL: int = 60


func _initialize() -> void:
	# Original run: play it once, keep its log and checkpoint hashes.
	var recorded_log := _build_command_log(0.031, 12)
	var original := _run_solo(RECORD_SEED, recorded_log)

	# Ghost replay: re-run the recorded log through a fresh core while a
	# different live run (different seed, different inputs) steps beside it.
	var live_log := _build_command_log(0.047, 8)
	var ghost_core := SimCoreScript.new()
	ghost_core.setup(RECORD_SEED)
	var live_core := SimCoreScript.new()
	live_core.setup(LIVE_SEED)

	var ghost_hashes: Array[int] = []
	for i in TICK_COUNT:
		live_core.step(live_log[i])
		ghost_core.step(recorded_log[i])
		if (i + 1) % HASH_INTERVAL == 0:
			ghost_hashes.append(ghost_core.state.state_hash())

	var failed := false
	for i in ghost_hashes.size():
		if ghost_hashes[i] != original.hashes[i]:
			printerr("FAIL: ghost hash mismatch at tick %d (%d != %d)" % [
				(i + 1) * HASH_INTERVAL, ghost_hashes[i], original.hashes[i]])
			failed = true

	var ghost_bytes: PackedByteArray = ghost_core.state.serialize()
	if ghost_bytes != original.final_bytes:
		printerr("FAIL: ghost final state differs from original run (%d vs %d bytes)" % [
			ghost_bytes.size(), original.final_bytes.size()])
		failed = true

	if failed:
		print("FAIL")
		quit(1)
		return

	print("PASS: recorded run replayed identically as ghost — %d ticks, %d checkpoints, %d bytes" % [
		TICK_COUNT, ghost_hashes.size(), ghost_bytes.size()])
	print("PASS")
	quit(0)


## Deterministic scripted input; parameters vary the aim sweep and fire
## rhythm so the original and live runs diverge.
func _build_command_log(aim_step: float, fire_window: int) -> Array[SimCommand]:
	var commands: Array[SimCommand] = []
	var directions: Array[Vector2] = [
		Vector2.RIGHT, Vector2(1, -1).normalized(), Vector2.UP,
		Vector2(-1, -1).normalized(), Vector2.LEFT, Vector2(-1, 1).normalized(),
		Vector2.DOWN, Vector2(1, 1).normalized(),
	]
	for i in TICK_COUNT:
		var cmd := SimCommand.new()
		cmd.move = directions[(i / 75) % directions.size()]
		cmd.aim = Vector2.RIGHT.rotated(float(i) * aim_step)
		cmd.fire = (i % 20) < fire_window
		cmd.dodge = (i % 96) == 90
		commands.append(cmd)
	return commands


func _run_solo(seed_value: int, commands: Array[SimCommand]) -> Dictionary:
	var core := SimCoreScript.new()
	core.setup(seed_value)
	var hashes: Array[int] = []
	for i in commands.size():
		core.step(commands[i])
		if (i + 1) % HASH_INTERVAL == 0:
			hashes.append(core.state.state_hash())
	return {
		"hashes": hashes,
		"final_bytes": core.state.serialize(),
	}
