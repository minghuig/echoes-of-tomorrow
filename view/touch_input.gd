class_name TouchInput
extends RefCounted
## Virtual touch controls for the web build on touchscreens (phones and
## tablets). Enabled only when running on web with a touchscreen — desktop
## web and native builds never see them. Pure view-layer input: this fills
## the same Command fields the keyboard/mouse path does; the sim cannot
## tell the difference.
##
## Layout: left half = floating move stick (anchors where the thumb lands),
## right half = drag to aim with auto-fire, bottom-right button = dodge.
## Touch-down points are also collected as taps for menu screens (death
## panel, the Between, credits).

const STICK_RADIUS: float = 70.0
const KNOB_RADIUS: float = 30.0
const DODGE_RADIUS: float = 46.0
## Extra slop around the dodge button so thumbs don't miss it.
const DODGE_HIT_SCALE: float = 1.35

var enabled: bool = false
var arena_size: Vector2 = Vector2.ZERO

var stick_anchor: Vector2 = Vector2.ZERO
var stick_vector: Vector2 = Vector2.ZERO
var aim_point: Vector2 = Vector2.ZERO

var _stick_finger: int = -1
var _aim_finger: int = -1
var _dodge_requested: bool = false
var _taps: Array[Vector2] = []


func setup(arena: Vector2, force_enabled: bool = false) -> void:
	arena_size = arena
	enabled = force_enabled or (
		OS.has_feature("web") and DisplayServer.is_touchscreen_available())


func dodge_center() -> Vector2:
	return Vector2(arena_size.x - 96.0, arena_size.y - 96.0)


func handle(event: InputEvent) -> void:
	if not enabled:
		return
	if event is InputEventScreenTouch:
		var touch := event as InputEventScreenTouch
		if touch.pressed:
			_press(touch.index, touch.position)
		else:
			_release(touch.index)
	elif event is InputEventScreenDrag:
		var drag := event as InputEventScreenDrag
		_drag(drag.index, drag.position)


func stick_active() -> bool:
	return _stick_finger != -1


func aim_active() -> bool:
	return _aim_finger != -1


## True once per press of the dodge button.
func consume_dodge() -> bool:
	var requested := _dodge_requested
	_dodge_requested = false
	return requested


## All touch-down points since last consumed (menu screens read these).
func consume_taps() -> Array[Vector2]:
	var taps := _taps.duplicate()
	_taps.clear()
	return taps


func _press(index: int, pos: Vector2) -> void:
	_taps.append(pos)
	if pos.distance_to(dodge_center()) <= DODGE_RADIUS * DODGE_HIT_SCALE:
		_dodge_requested = true
		return
	if pos.x < arena_size.x * 0.5:
		if _stick_finger == -1:
			_stick_finger = index
			stick_anchor = pos
			stick_vector = Vector2.ZERO
	elif _aim_finger == -1:
		_aim_finger = index
		aim_point = pos


func _drag(index: int, pos: Vector2) -> void:
	if index == _stick_finger:
		stick_vector = (pos - stick_anchor) / STICK_RADIUS
		if stick_vector.length_squared() > 1.0:
			stick_vector = stick_vector.normalized()
	elif index == _aim_finger:
		aim_point = pos


func _release(index: int) -> void:
	if index == _stick_finger:
		_stick_finger = -1
		stick_vector = Vector2.ZERO
	elif index == _aim_finger:
		_aim_finger = -1
