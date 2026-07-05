extends SceneTree
## Determinism harness: builds a scripted ~600-tick command log (movement,
## aim sweeps, firing bursts, dodges — generated, not recorded), runs it
## twice through fresh SimCore instances with the same seed, and compares
## state_hash() every 60 ticks plus the final serialized state
## byte-for-byte. Exits 0 on PASS, 1 on FAIL.
##
##   godot --headless --path . --script res://tests/test_determinism.gd

const SimCoreScript := preload("res://sim/sim_core.gd")
const SimCommand := preload("res://sim/command.gd")

const SEED: int = 1337
const TICK_COUNT: int = 900
const HASH_INTERVAL: int = 60


func _initialize() -> void:
	var log_a := _build_command_log()
	var log_b := _build_command_log()

	var run_a := _run(log_a)
	var run_b := _run(log_b)

	var failed := false
	for i in run_a.hashes.size():
		if run_a.hashes[i] != run_b.hashes[i]:
			var tick: int = (i + 1) * HASH_INTERVAL
			printerr("FAIL: state hash mismatch at tick %d (%d != %d)" % [
				tick, run_a.hashes[i], run_b.hashes[i]])
			failed = true

	if run_a.final_bytes != run_b.final_bytes:
		printerr("FAIL: final serialized state differs (%d vs %d bytes)" % [
			run_a.final_bytes.size(), run_b.final_bytes.size()])
		failed = true

	if failed:
		print("FAIL")
		quit(1)
		return

	print("PASS: %d ticks, %d hash checkpoints, final state %d bytes identical" % [
		TICK_COUNT, run_a.hashes.size(), run_a.final_bytes.size()])
	print("PASS")
	quit(0)


## Deterministic scripted input: eight direction phases, a continuous aim
## sweep, fire bursts, and a dodge every ~1.6s.
func _build_command_log() -> Array[SimCommand]:
	var commands: Array[SimCommand] = []
	var directions: Array[Vector2] = [
		Vector2.RIGHT, Vector2(1, -1).normalized(), Vector2.UP,
		Vector2(-1, -1).normalized(), Vector2.LEFT, Vector2(-1, 1).normalized(),
		Vector2.DOWN, Vector2(1, 1).normalized(),
	]
	for i in TICK_COUNT:
		var cmd := SimCommand.new()
		cmd.move = directions[(i / 75) % directions.size()]
		cmd.aim = Vector2.RIGHT.rotated(float(i) * 0.031)
		cmd.fire = (i % 20) < 12
		cmd.dodge = (i % 96) == 90
		commands.append(cmd)
	return commands


func _run(commands: Array[SimCommand]) -> Dictionary:
	var core := SimCoreScript.new()
	core.setup(SEED)
	var hashes: Array[int] = []
	for i in commands.size():
		core.step(commands[i])
		if (i + 1) % HASH_INTERVAL == 0:
			hashes.append(core.state.state_hash())
	return {
		"hashes": hashes,
		"final_bytes": core.state.serialize(),
	}
