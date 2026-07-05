extends Node2D
## Screen-space overlay on its own CanvasLayer (unaffected by camera shake):
## vignette, scanlines, rolling holo-refresh band, diegetic training-sim HUD,
## and the animated CLEAR banner. Read-only over sim state.

const SimCoreScript := preload("res://sim/sim_core.gd")

const COLOR_HUD := Color("3fd0d4")
const COLOR_CLEAR := Color("aef2f4")

const CLEAR_TITLE := "SIMULATION CLEAR"
const CLEAR_SUB := "ALL TARGETS NEUTRALIZED — AWAITING EVALUATION"

var core: SimCoreScript
var total_targets: int = 0

var _time: float = 0.0
var _clear_t: float = -1.0
var _vignette_tex: GradientTexture2D
var _band_tex: GradientTexture2D
var _scan_tex: ImageTexture


func _ready() -> void:
	texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED

	var vg := Gradient.new()
	vg.offsets = PackedFloat32Array([0.0, 0.55, 1.0])
	vg.colors = PackedColorArray(
		[Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.42)])
	_vignette_tex = GradientTexture2D.new()
	_vignette_tex.gradient = vg
	_vignette_tex.fill = GradientTexture2D.FILL_RADIAL
	_vignette_tex.fill_from = Vector2(0.5, 0.5)
	_vignette_tex.fill_to = Vector2(0.5, -0.15)
	_vignette_tex.width = 512
	_vignette_tex.height = 512

	var bg := Gradient.new()
	bg.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	bg.colors = PackedColorArray(
		[Color(1.0, 1.0, 1.0, 0.0), Color(1.0, 1.0, 1.0, 0.045), Color(1.0, 1.0, 1.0, 0.0)])
	_band_tex = GradientTexture2D.new()
	_band_tex.gradient = bg
	_band_tex.fill_from = Vector2(0.0, 0.0)
	_band_tex.fill_to = Vector2(0.0, 1.0)
	_band_tex.width = 8
	_band_tex.height = 64

	var img := Image.create(1, 3, false, Image.FORMAT_RGBA8)
	img.set_pixel(0, 0, Color(0.0, 0.0, 0.0, 0.0))
	img.set_pixel(0, 1, Color(0.0, 0.0, 0.0, 0.0))
	img.set_pixel(0, 2, Color(0.0, 0.0, 0.0, 0.10))
	_scan_tex = ImageTexture.create_from_image(img)


func _process(delta: float) -> void:
	_time += delta
	if core != null and core.state.blocks.is_empty():
		_clear_t = 0.0 if _clear_t < 0.0 else _clear_t + delta
	queue_redraw()


func _draw() -> void:
	if core == null:
		return
	var screen := core.state.arena_size
	var full := Rect2(Vector2.ZERO, screen)

	# Rolling holo-refresh band.
	var band_y := wrapf(_time * 46.0, -100.0, screen.y + 100.0)
	draw_texture_rect(_band_tex, Rect2(0.0, band_y, screen.x, 90.0), false)

	draw_texture_rect(_vignette_tex, full, false)
	draw_texture_rect(_scan_tex, full, true)

	_draw_hud(screen)
	if _clear_t >= 0.0:
		_draw_clear_banner(screen)


func _draw_hud(screen: Vector2) -> void:
	var font := ThemeDB.fallback_font
	var col := Color(COLOR_HUD, 0.5)
	var dim := Color(COLOR_HUD, 0.32)
	var state := core.state

	draw_string(
		font, Vector2(24.0, 32.0), "ASSET-7 // COMBAT TRAINING SIM",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
	draw_string(
		font, Vector2(24.0, 50.0), "ITERATION 001   T+" + str(state.tick).pad_zeros(6),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, dim)

	var targets := "TARGETS %d / %d" % [state.blocks.size(), total_targets]
	draw_string(
		font, Vector2(0.0, 32.0), targets,
		HORIZONTAL_ALIGNMENT_RIGHT, screen.x - 24.0, 13, col)
	draw_string(
		font, Vector2(0.0, 50.0), "INTEGRITY %d%%" % state.player_hp,
		HORIZONTAL_ALIGNMENT_RIGHT, screen.x - 24.0, 13, dim)


func _draw_clear_banner(screen: Vector2) -> void:
	var center := screen * 0.5
	var appear := clampf(_clear_t / 0.45, 0.0, 1.0)
	var eased := 1.0 - pow(1.0 - appear, 3.0)
	var flicker := 0.92 + 0.08 * sin(_time * 37.0) * sin(_time * 13.0)

	draw_rect(Rect2(Vector2.ZERO, screen), Color(0.0, 0.0, 0.0, 0.38 * eased))

	# Horizontal rules expanding outward from center.
	var rule_len := 380.0 * eased
	var rule_col := Color(COLOR_HUD, 0.55 * eased)
	for y_off: float in [-64.0, 46.0]:
		var y := center.y + y_off
		draw_line(
			Vector2(center.x - rule_len, y), Vector2(center.x + rule_len, y), rule_col, 2.0)

	# Title scales in with a soft glow pass under the crisp pass.
	var s := 1.18 - 0.18 * eased
	draw_set_transform(center * (1.0 - s), 0.0, Vector2(s, s))
	_draw_spaced_text(
		center + Vector2(0.0, 2.0), CLEAR_TITLE, 64, 10.0,
		Color(COLOR_HUD, 0.28 * eased * flicker))
	_draw_spaced_text(
		center, CLEAR_TITLE, 64, 10.0, Color(COLOR_CLEAR, eased * flicker))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	if _clear_t > 0.35:
		var sub_a := clampf((_clear_t - 0.35) / 0.4, 0.0, 1.0)
		_draw_spaced_text(
			center + Vector2(0.0, 34.0), CLEAR_SUB, 15, 4.0,
			Color(COLOR_HUD, 0.75 * sub_a * flicker))


## draw_string has no letter-spacing control, so lay glyphs out by hand.
func _draw_spaced_text(
	center: Vector2, text: String, font_size: int, spacing: float, color: Color
) -> void:
	var font := ThemeDB.fallback_font
	var widths: Array[float] = []
	var total := -spacing
	for ch in text:
		var w := font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		widths.append(w)
		total += w + spacing
	var x := center.x - total * 0.5
	for i in text.length():
		draw_string(
			font, Vector2(x, center.y), text[i],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, color)
		x += widths[i] + spacing
