class_name DisplaySettings
extends RefCounted
## Window size selection, persisted to user://display_settings.json across
## launches. Pure view cosmetics: the base viewport stays 1280x720
## (project.godot), and Godot's canvas_items stretch mode does the scaling,
## so picking a different window size never touches sim/gameplay coordinates.

const SAVE_PATH := "user://display_settings.json"

## Windowed size presets; PRESETS.size() itself (one past the last index) is
## the "fullscreen" entry.
const PRESETS: Array[Vector2i] = [
	Vector2i(1280, 720),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
]
const LABELS: Array[String] = ["1280 x 720", "1600 x 900", "1920 x 1080", "FULLSCREEN"]

var index: int = 0


func load_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(SAVE_PATH))
	if parsed is Dictionary:
		index = clampi(int(parsed.get("index", 0)), 0, LABELS.size() - 1)


func save_to_disk() -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if file == null:
		push_warning("DisplaySettings: cannot write " + SAVE_PATH)
		return
	file.store_string(JSON.stringify({"index": index}))


func label() -> String:
	return LABELS[index]


func cycle(delta: int) -> void:
	index = (index + delta + LABELS.size()) % LABELS.size()


## Push the current selection onto the actual OS window.
func apply(window: Window) -> void:
	if index >= PRESETS.size():
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	window.size = PRESETS[index]
	var screen_size := DisplayServer.screen_get_size(window.current_screen)
	if screen_size.x > 0 and screen_size.y > 0:
		window.position = (screen_size - window.size) / 2
