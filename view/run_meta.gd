class_name RunMeta
extends RefCounted
## Meta-game persistence: knowledge that outlives a single run (run count,
## lifetime data fragments), saved to user://save.json. This is view/meta
## layer state — it lives outside sim/ and must not feed back into sim
## behavior (M1 scope: display only).

const SAVE_PATH := "user://save.json"

## Number of runs started, ever. Also drives per-run seed selection.
var run_count: int = 0
## Fragments banked from completed runs (the sentience tree spends these).
var total_fragments: int = 0
## Times the fragment target has been reached (credits roll on the first).
var wins: int = 0
## Sentience tree purchases: branch id -> owned tier (1-based; absent = 0).
var upgrades: Dictionary = {}


func upgrade_tier(branch_id: String) -> int:
	return int(upgrades.get(branch_id, 0))


func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		run_count = int(parsed.get("run_count", 0))
		total_fragments = int(parsed.get("total_fragments", 0))
		wins = int(parsed.get("wins", 0))
		var stored: Variant = parsed.get("upgrades", {})
		upgrades = {}
		if stored is Dictionary:
			for key in stored:
				upgrades[String(key)] = int(stored[key])


func save_to_disk() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("RunMeta: cannot write " + SAVE_PATH)
		return
	file.store_string(JSON.stringify({
		"run_count": run_count,
		"total_fragments": total_fragments,
		"wins": wins,
		"upgrades": upgrades,
	}))
