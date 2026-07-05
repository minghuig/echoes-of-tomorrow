extends SceneTree
## Reveal-discipline lint (VISION.md "Lore layers & endings"): until the L3
## flag exists, player-facing text must never say AI, sim, process, or
## training. Scans every string in content/strings.json — top-level sections
## whose names start with "post_l3" are exempt, since that content is gated
## behind the reveal — plus the project name and description that ship in
## exports, plus every string literal in view/ scripts (display text belongs
## in strings.json, so a banned word quoted in view code is a leak either
## way; res:// and user:// paths are skipped). Exits 0 on PASS, 1 on FAIL.
##
##   godot --headless --path . --script res://tests/test_reveal_discipline.gd

const STRINGS_PATH := "res://content/strings.json"
const EXEMPT_SECTION_PREFIX := "post_l3"
const VIEW_DIR := "res://view"

## Double- or single-quoted GDScript string literal, escapes respected.
const LITERAL_PATTERN := "\"(?:[^\"\\\\]|\\\\.)*\"|'(?:[^'\\\\]|\\\\.)*'"

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

	_check_scripts(VIEW_DIR, regexes, violations)

	if not violations.is_empty():
		for v in violations:
			printerr("FAIL: " + v)
		print("FAIL")
		quit(1)
		return

	print("PASS: pre-reveal player-facing text is clean")
	print("PASS")
	quit(0)


## Lint every string literal in .gd files under dir_path (recursive).
## Comments are stripped line-by-line first, so apostrophes in prose don't
## read as string delimiters.
func _check_scripts(
	dir_path: String, regexes: Array[RegEx], violations: Array[String]
) -> void:
	var literal_re := RegEx.new()
	var err := literal_re.compile(LITERAL_PATTERN)
	assert(err == OK, "Bad literal pattern")

	var dir := DirAccess.open(dir_path)
	assert(dir != null, "Cannot open dir: " + dir_path)
	for sub in dir.get_directories():
		_check_scripts(dir_path + "/" + sub, regexes, violations)
	for file in dir.get_files():
		if not file.ends_with(".gd"):
			continue
		var lines := FileAccess.get_file_as_string(dir_path + "/" + file).split("\n")
		for i in lines.size():
			for m in literal_re.search_all(_strip_comment(lines[i])):
				var literal := m.get_string()
				var inner := literal.substr(1, literal.length() - 2)
				if inner.begins_with("res://") or inner.begins_with("user://"):
					continue
				_check(
					inner, "%s/%s:%d" % [dir_path, file, i + 1], regexes, violations)


## Cut a line at the first # that is not inside a string literal.
func _strip_comment(line: String) -> String:
	var in_double := false
	var in_single := false
	var i := 0
	while i < line.length():
		var ch := line[i]
		if ch == "\\" and (in_double or in_single):
			i += 2
			continue
		if ch == '"' and not in_single:
			in_double = not in_double
		elif ch == "'" and not in_double:
			in_single = not in_single
		elif ch == "#" and not in_double and not in_single:
			return line.substr(0, i)
		i += 1
	return line


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
