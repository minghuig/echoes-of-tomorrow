extends Node
## Crossfading music bed with on-demand track loading. Two AudioStreamPlayers
## ping-pong: a new track fades up on the idle player while the outgoing one
## fades down, so scene changes (title <-> beach <-> Between) segue instead of
## hard-cutting.
##
## Tracks are referenced by key (not by stream), so callers never hold the audio
## and the node owns *when* each bed becomes available:
##   - Web: the audio is NOT in the export pck (see export_presets exclude_filter
##     + the CI step that copies assets/music/*.mp3 next to index.html). Each
##     track is fetched with HTTPRequest on demand, so the game boots instantly
##     and music streams in a moment later instead of blocking the initial pck
##     download.
##   - Editor / native: the mp3s are ordinary imported resources, loaded
##     synchronously from disk/pck.
## Ask for a key before its stream has arrived and it simply starts the instant
## it loads, if that key is still the one wanted.
##
## Pure view flavor — the sim never sees music (the SFX precedent in
## DECISIONS.md). Fades run on wall-clock `_process` delta; nothing here touches
## sim time, the command log, or the seeded RNG, so determinism is untouched.

## Seconds for a full crossfade (out track to silence, in track to full).
const FADE_SECS: float = 1.6
## Full-volume level for the active track; per-track trims can go lower.
const BASE_DB: float = -5.0
const SILENCE_DB: float = -60.0

## Where source mp3s live in the project (editor/native load path).
const SRC_DIR: String = "res://assets/music/"
## Where the CI copies them beside index.html on web deploys (fetch path),
## relative to the running page so PR/latest subdirectories resolve correctly.
const WEB_DIR: String = "audio/"

var _players: Array[AudioStreamPlayer] = []
## Per-player linear gain (0..1) and the gain each is easing toward.
var _gain: Array[float] = [0.0, 0.0]
var _goal: Array[float] = [0.0, 0.0]
## Index of the player owning the current track, or -1 when faded to silence.
var _active: int = -1
## Key of the track currently playing/fading in ("" = silence), and the key most
## recently requested (may differ while its stream is still downloading).
var _current_key: String = ""
var _desired_key: String = ""

## key -> AudioStream, populated as tracks finish loading.
var _streams: Dictionary = {}

## Web-only: one HTTPRequest reused for a serial fetch queue (keeps memory and
## bandwidth bounded; the title bed is queued first so it arrives soonest).
var _http: HTTPRequest = null
var _fetch_queue: Array = []
var _fetching: bool = false


func _ready() -> void:
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.volume_db = SILENCE_DB
		add_child(player)
		_players.append(player)
	if OS.has_feature("web"):
		_http = HTTPRequest.new()
		add_child(_http)
		_http.request_completed.connect(_on_fetch_completed)


## Register the tracks to make available: `map` is key -> mp3 filename. On web
## these queue for background download; elsewhere they load synchronously now.
func request_tracks(map: Dictionary) -> void:
	for key: String in map:
		var file: String = map[key]
		if OS.has_feature("web"):
			_fetch_queue.append({"key": key, "file": file})
		else:
			var stream := load(SRC_DIR + file) as AudioStream
			if stream != null:
				_loop(stream)
				_streams[key] = stream
	if OS.has_feature("web"):
		_pump_queue()


func _pump_queue() -> void:
	if _fetching or _fetch_queue.is_empty():
		return
	_fetching = true
	var job: Dictionary = _fetch_queue.pop_front()
	_http.set_meta("key", job["key"])
	var err := _http.request(WEB_DIR + String(job["file"]))
	if err != OK:
		push_warning("music: fetch request failed for %s (%d)" % [job["file"], err])
		_fetching = false
		_pump_queue()


func _on_fetch_completed(
	result: int, code: int, _headers: PackedStringArray, body: PackedByteArray
) -> void:
	var key := String(_http.get_meta("key", ""))
	_fetching = false
	if result == HTTPRequest.RESULT_SUCCESS and code == 200 and not body.is_empty():
		var mp3 := AudioStreamMP3.new()
		mp3.data = body
		mp3.loop = true
		_streams[key] = mp3
		# If the player is still waiting on exactly this track, start it now.
		if _desired_key == key and _current_key != key:
			_start(key)
	else:
		push_warning("music: could not fetch track '%s' (result %d, code %d)" % [key, result, code])
	_pump_queue()


## Crossfade to the track registered under `key` ("" fades to silence). A no-op
## once that key is already the active track, so callers can invoke this every
## frame from the current mode without restarting audio. If the track has not
## finished loading, the request is remembered and playback begins the moment it
## arrives (via _on_fetch_completed).
func play_track(key: String) -> void:
	if key.is_empty():
		stop()
		return
	_desired_key = key
	if key == _current_key and _active >= 0:
		return
	if not _streams.has(key):
		# Not loaded yet: fade out whatever is playing so the new scene isn't
		# scored by the old bed while its own track downloads.
		if _active >= 0:
			_goal[_active] = 0.0
		_current_key = ""
		return
	_start(key)


func _start(key: String) -> void:
	_current_key = key
	var nxt := 0 if _active != 0 else 1
	var player := _players[nxt]
	player.stream = _streams[key]
	player.volume_db = SILENCE_DB
	_gain[nxt] = 0.0
	player.play()
	_goal[nxt] = 1.0
	if _active >= 0:
		_goal[_active] = 0.0
	_active = nxt


## Fade everything out (silent scenes with no track of their own).
func stop() -> void:
	_desired_key = ""
	if _current_key.is_empty() and _active < 0:
		return
	_current_key = ""
	_goal[0] = 0.0
	_goal[1] = 0.0
	_active = -1


func _loop(stream: AudioStream) -> void:
	if stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true


func _process(delta: float) -> void:
	var step := delta / FADE_SECS
	for i in 2:
		_gain[i] = move_toward(_gain[i], _goal[i], step)
		var player := _players[i]
		if _gain[i] <= 0.0005:
			player.volume_db = SILENCE_DB
			if player.playing and _goal[i] == 0.0:
				player.stop()
		else:
			player.volume_db = BASE_DB + linear_to_db(_gain[i])
