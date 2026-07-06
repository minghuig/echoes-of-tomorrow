extends RefCounted
## Shared canvas drawing helpers for the view layer.


## Draw a capsule (two circles bridged by a rect) rotated around its center.
## Resets the canvas transform before returning.
static func capsule(
	ci: CanvasItem,
	center: Vector2,
	radius: float,
	half_gap: float,
	rot: float,
	color: Color,
) -> void:
	ci.draw_set_transform(center, rot, Vector2.ONE)
	ci.draw_circle(Vector2(0.0, -half_gap), radius, color)
	ci.draw_circle(Vector2(0.0, half_gap), radius, color)
	ci.draw_rect(
		Rect2(Vector2(-radius, -half_gap), Vector2(radius * 2.0, half_gap * 2.0)), color)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
