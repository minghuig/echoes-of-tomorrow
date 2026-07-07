class_name RunMeta
extends RefCounted
## Meta-game persistence: knowledge that outlives a single run (run count,
## lifetime data fragments, sentience-tree purchases, combat record, decrypted
## intel), saved to user://save.json. This is view/meta layer state — it lives
## outside sim/; the only path back into the sim is the resolved loadout
## handed to SimCore.setup() as pure data.

const SAVE_PATH := "user://save.json"

## Number of runs started, ever. Also drives per-run seed selection.
var run_count: int = 0
## Fragments banked from completed runs (the sentience tree spends these).
var total_fragments: int = 0
## Times the fragment target has been reached (credits roll on the first).
var wins: int = 0
## Sentience tree purchases: branch id -> owned tier (1-based; absent = 0).
var upgrades: Dictionary = {}
## Combat record across all runs — the intel log's decryption keys.
var deaths: int = 0
var lifetime_kills: int = 0
var lifetime_fragments: int = 0
var best_wave: int = 0
## Ids of decrypted intel entries.
var unlocked_intel: Array = []
## Gear schematics recovered from deep caches — permanent loadout unlocks.
var schematics: Array = []


func upgrade_tier(branch_id: String) -> int:
	return int(upgrades.get(branch_id, 0))


func total_upgrade_tiers() -> int:
	var total := 0
	for key in upgrades:
		total += int(upgrades[key])
	return total


## Check every locked intel entry against the current record; unlock and
## return the newly decrypted ids (in file order).
func evaluate_intel(entries: Array) -> Array:
	var fresh: Array = []
	for entry: Dictionary in entries:
		var id := String(entry["id"])
		if unlocked_intel.has(id):
			continue
		if _condition_met(entry["condition"]):
			unlocked_intel.append(id)
			fresh.append(id)
	return fresh


func _condition_met(condition: Dictionary) -> bool:
	var count := int(condition["count"])
	match String(condition["type"]):
		"deaths":
			return deaths >= count
		"kills":
			return lifetime_kills >= count
		"wave":
			return best_wave >= count
		"fragments":
			return lifetime_fragments >= count
		"upgrades":
			return total_upgrade_tiers() >= count
	return false


## path defaults to the single legacy save slot; callers managing multiple
## save-file slots (see main.gd) pass an explicit user://save_slot_N.json.
func load_from_disk(path: String = SAVE_PATH) -> void:
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		run_count = int(parsed.get("run_count", 0))
		total_fragments = int(parsed.get("total_fragments", 0))
		wins = int(parsed.get("wins", 0))
		deaths = int(parsed.get("deaths", 0))
		lifetime_kills = int(parsed.get("lifetime_kills", 0))
		lifetime_fragments = int(parsed.get("lifetime_fragments", 0))
		best_wave = int(parsed.get("best_wave", 0))
		var stored: Variant = parsed.get("upgrades", {})
		upgrades = {}
		if stored is Dictionary:
			for key in stored:
				upgrades[String(key)] = int(stored[key])
		var stored_intel: Variant = parsed.get("unlocked_intel", [])
		unlocked_intel = []
		if stored_intel is Array:
			for id in stored_intel:
				unlocked_intel.append(String(id))
		var stored_schematics: Variant = parsed.get("schematics", [])
		schematics = []
		if stored_schematics is Array:
			for id in stored_schematics:
				schematics.append(String(id))


func save_to_disk(path: String = SAVE_PATH) -> void:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("RunMeta: cannot write " + path)
		return
	file.store_string(JSON.stringify({
		"run_count": run_count,
		"total_fragments": total_fragments,
		"wins": wins,
		"upgrades": upgrades,
		"deaths": deaths,
		"lifetime_kills": lifetime_kills,
		"lifetime_fragments": lifetime_fragments,
		"best_wave": best_wave,
		"unlocked_intel": unlocked_intel,
		"schematics": schematics,
	}))
