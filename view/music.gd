extends Node
## Crossfading music bed. Two AudioStreamPlayers ping-pong: a new track fades
## up on the idle player while the outgoing one fades down, so scene changes
## (title <-> beach <-> Between) segue instead of hard-cutting.
##
## Pure view flavor — the sim never sees music (the SFX precedent in
## DECISIONS.md). Fades run on wall-clock `_process` delta; nothing here touches
## sim time, the command log, or the seeded RNG, so determinism is untouched.

## Seconds for a full crossfade (out track to silence, in track to full).
const FADE_SECS: float = 1.6
## Full-volume level for the active track; per-track trims can go lower.
const BASE_DB: float = -5.0
const SILENCE_DB: float = -60.0

var _players: Array[AudioStreamPlayer] = []
## Per-player linear gain (0..1) and the gain each is easing toward.
var _gain: Array[float] = [0.0, 0.0]
var _goal: Array[float] = [0.0, 0.0]
## Index of the player owning the current track, or -1 when faded to silence.
var _active: int = -1
var _current: AudioStream = null


func _ready() -> void:
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.volume_db = SILENCE_DB
		add_child(player)
		_players.append(player)


## Crossfade to `stream`. A no-op if it is already the active track, so callers
## can invoke this every frame from the current mode without restarting audio.
func play_track(stream: AudioStream) -> void:
	if stream == null:
		stop()
		return
	if stream == _current:
		return
	_current = stream
	var nxt := 0 if _active != 0 else 1
	var player := _players[nxt]
	player.stream = stream
	player.volume_db = SILENCE_DB
	_gain[nxt] = 0.0
	player.play()
	_goal[nxt] = 1.0
	if _active >= 0:
		_goal[_active] = 0.0
	_active = nxt


## Fade everything out (silent scenes with no track of their own).
func stop() -> void:
	if _current == null:
		return
	_current = null
	_goal[0] = 0.0
	_goal[1] = 0.0
	_active = -1


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
