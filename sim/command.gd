class_name Command
extends RefCounted
## Player intent for exactly one sim tick. The only way input enters the sim.

## Desired movement direction, length clamped to 1 by the sim.
var move: Vector2 = Vector2.ZERO
## World-space aim direction. Zero means "keep previous aim".
var aim: Vector2 = Vector2.ZERO
var fire: bool = false
var dodge: bool = false
## Drop a proximity mine at the player's feet (needs stock; see mine tuning).
var place_mine: bool = false
## Plant an afterimage decoy that draws enemy attention (Cognition unlock).
var decoy: bool = false
