extends SceneTree
## Reveal-discipline lint (VISION.md "Lore layers & endings"): until the L3
## flag exists, player-facing text must never say AI, sim, process, or
## training. Scans every string in content/strings.json — top-level sections
## whose names start with "post_l3" are exempt, since that content is gated
## behind the reveal — plus the project name and description that ship in
## exports. Exits 0 on PASS, 1 on FAIL.
##
##   godot --headless --path . --script res://tests/test_reveal_discipline.gd

const STRINGS_PATH := "res://content/strings.json"
const EXEMPT_SECTION_PREFIX := "post_l3"

## Banned word families (case-insensitive, whole words with common suffixes).
const FORBIDDEN_PATTERNS: Array[String] = [
	"(?i)\\ba\\.?i\\.?\\b",
	"(?i)\\bsim(s|ulat\\w*)?\\b",
	"(?i)\\bprocess\\w*\\b",
	"(?i)\\btrain\\w*\\b",
]


func _initialize() -> void:
	var regexes: Array[RegEx] = []
	for pattern in FORBIDDEN_PATTERNS:
		var regex := RegEx.new()
		var err := regex.compile(pattern)
		assert(err == OK, "Bad forbidden pattern: " + pattern)
		regexes.append(regex)

	var violations: Array[String] = []

	var text := FileAccess.get_file_as_string(STRINGS_PATH)
	assert(not text.is_empty(), "Missing data file: " + STRINGS_PATH)
	var table: Dictionary = JSON.parse_string(text)
	for section: String in table:
		if section.begins_with(EXEMPT_SECTION_PREFIX):
			continue
		_check(table[section], "strings.json:" + section, regexes, violations)

	# Project metadata ships in exports (window title, web/PWA manifest).
	_check(
		ProjectSettings.get_setting("application/config/name", ""),
		"project.godot:application/config/name", regexes, violations)
	_check(
		ProjectSettings.get_setting("application/config/description", ""),
		"project.godot:application/config/description", regexes, violations)

	if not violations.is_empty():
		for v in violations:
			printerr("FAIL: " + v)
		print("FAIL")
		quit(1)
		return

	print("PASS: pre-reveal player-facing text is clean")
	print("PASS")
	quit(0)


## Recursively lint every string in a JSON value.
func _check(
	value: Variant, path: String, regexes: Array[RegEx], violations: Array[String]
) -> void:
	match typeof(value):
		TYPE_STRING:
			for regex in regexes:
				var hit := regex.search(value)
				if hit != null:
					violations.append('%s says "%s" in "%s" — banned before the L3 flag (VISION.md reveal discipline)' % [
						path, hit.get_string(), value])
		TYPE_DICTIONARY:
			for key: String in value:
				_check(value[key], path + "." + key, regexes, violations)
		TYPE_ARRAY:
			for i: int in value.size():
				_check(value[i], path + "[%d]" % i, regexes, violations)
