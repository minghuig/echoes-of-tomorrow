class_name SimState
extends RefCounted
## Complete simulation state. Plain data; only SimCore mutates it.
## serialize() has a stable field order — it defines the determinism contract.

class Projectile extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var ttl: int = 0
	var damage: int = 0

class Block extends RefCounted:
	var pos: Vector2 = Vector2.ZERO  # top-left corner
	var size: Vector2 = Vector2.ZERO
	var hp: int = 0
	## Authored per-block (seawall segments are tougher than scatter cover).
	var max_hp: int = 0

## What a destroyed block leaves behind: a slow-patch of debris. No cover
## value — degraded terrain, not deleted terrain.
class Rubble extends RefCounted:
	var pos: Vector2 = Vector2.ZERO  # top-left corner
	var size: Vector2 = Vector2.ZERO

class Enemy extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var vel: Vector2 = Vector2.ZERO
	var hp: int = 0
	var type: String = ""
	var fire_cooldown: int = 0
	var contact_cooldown: int = 0
	## Attack state machine: 0 roam, 1 windup, 2 commit, 3 recover (constants
	## live in SimCore). Windup telegraphs, commit is locked-in, recover is the
	## punish window.
	var phase: int = 0
	## Ticks remaining in the current non-roam phase.
	var phase_ticks: int = 0
	## Direction locked at windup start; the commit follows it exactly, so
	## telegraphs never lie.
	var attack_dir: Vector2 = Vector2.ZERO
	## Volley shots still to fire this commit.
	var shots_left: int = 0

class PendingSpawn extends RefCounted:
	var tick: int = 0
	var type: String = ""
	var pos: Vector2 = Vector2.ZERO

## A scheduled artillery shell: telegraphed at pos until land_tick, then AoE
## damage to everything in radius and a crater left behind.
class Impact extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var land_tick: int = 0
	var radius: float = 0.0
	var damage: int = 0
	var crater_radius: float = 0.0

## Rough ground left by artillery: slows ground movers inside for the rest of
## the run. The war remodels the map.
class Crater extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var radius: float = 0.0

## A lootable crate on the map: crack it (player fire) for salvage. kind is
## "supply" or "schematic" (the deep cache that unlocks gear permanently).
class Cache extends RefCounted:
	var pos: Vector2 = Vector2.ZERO  # top-left corner
	var size: Vector2 = Vector2.ZERO
	var hp: int = 0
	var kind: String = ""

## A dropped salvage item, collected by walking over it before it expires.
class Pickup extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var kind: String = ""
	var ttl: int = 0

## A planted proximity mine: arms after arm_ticks, then detonates on the
## first enemy inside the trigger radius.
class Mine extends RefCounted:
	var pos: Vector2 = Vector2.ZERO
	var arm_ticks: int = 0

var tick: int = 0

var player_pos: Vector2 = Vector2.ZERO
var player_vel: Vector2 = Vector2.ZERO
var player_aim: Vector2 = Vector2.RIGHT
var player_hp: int = 0
var dodge_vel: Vector2 = Vector2.ZERO
var dodge_cooldown: int = 0
var fire_cooldown: int = 0
## Ticks of dodge invulnerability remaining.
var iframe_ticks: int = 0
## True once player_hp hit 0; the sim freezes (only tick advances).
var player_down: bool = false

## Data fragments earned this run (blocks + enemy kills).
var fragments: int = 0
var kills: int = 0
## Next wave to be scheduled.
var wave_index: int = 0
## Next authored assault event to be scheduled.
var event_index: int = 0

var projectiles: Array[Projectile] = []
var blocks: Array[Block] = []
var enemies: Array[Enemy] = []
var enemy_projectiles: Array[Projectile] = []
var pending_spawns: Array[PendingSpawn] = []
var pending_impacts: Array[Impact] = []
var craters: Array[Crater] = []
var rubble: Array[Rubble] = []
var caches: Array[Cache] = []
var pickups: Array[Pickup] = []
var mines: Array[Mine] = []

## Mine dispenser state (stock comes from the loadout; pickups restock it).
var mine_stock: int = 0
var mine_cooldown: int = 0
## Overcharge salvage stacks: each one scales the fire cooldown down.
var overcharge_stacks: int = 0
## Schematic ids recovered this run (banked by the meta layer at run end).
var schematics_found: Array[String] = []

var arena_size: Vector2 = Vector2.ZERO
## Per-seed tide: everything above this y is surf and slows ground movers.
var surf_line: float = 0.0


func serialize() -> PackedByteArray:
	var buf := StreamPeerBuffer.new()
	buf.put_u32(tick)
	_put_vec2(buf, player_pos)
	_put_vec2(buf, player_vel)
	_put_vec2(buf, player_aim)
	buf.put_32(player_hp)
	_put_vec2(buf, dodge_vel)
	buf.put_32(dodge_cooldown)
	buf.put_32(fire_cooldown)
	buf.put_32(iframe_ticks)
	buf.put_32(1 if player_down else 0)
	buf.put_32(fragments)
	buf.put_32(kills)
	buf.put_32(wave_index)
	buf.put_32(event_index)
	buf.put_u32(projectiles.size())
	for p: Projectile in projectiles:
		_put_projectile(buf, p)
	buf.put_u32(blocks.size())
	for b: Block in blocks:
		_put_vec2(buf, b.pos)
		_put_vec2(buf, b.size)
		buf.put_32(b.hp)
		buf.put_32(b.max_hp)
	buf.put_u32(enemies.size())
	for e: Enemy in enemies:
		_put_vec2(buf, e.pos)
		_put_vec2(buf, e.vel)
		buf.put_32(e.hp)
		buf.put_utf8_string(e.type)
		buf.put_32(e.fire_cooldown)
		buf.put_32(e.contact_cooldown)
		buf.put_32(e.phase)
		buf.put_32(e.phase_ticks)
		_put_vec2(buf, e.attack_dir)
		buf.put_32(e.shots_left)
	buf.put_u32(enemy_projectiles.size())
	for p: Projectile in enemy_projectiles:
		_put_projectile(buf, p)
	buf.put_u32(pending_spawns.size())
	for s: PendingSpawn in pending_spawns:
		buf.put_32(s.tick)
		buf.put_utf8_string(s.type)
		_put_vec2(buf, s.pos)
	buf.put_u32(pending_impacts.size())
	for imp: Impact in pending_impacts:
		_put_vec2(buf, imp.pos)
		buf.put_32(imp.land_tick)
		buf.put_float(imp.radius)
		buf.put_32(imp.damage)
		buf.put_float(imp.crater_radius)
	buf.put_u32(craters.size())
	for c: Crater in craters:
		_put_vec2(buf, c.pos)
		buf.put_float(c.radius)
	buf.put_u32(rubble.size())
	for r: Rubble in rubble:
		_put_vec2(buf, r.pos)
		_put_vec2(buf, r.size)
	buf.put_u32(caches.size())
	for c: Cache in caches:
		_put_vec2(buf, c.pos)
		_put_vec2(buf, c.size)
		buf.put_32(c.hp)
		buf.put_utf8_string(c.kind)
	buf.put_u32(pickups.size())
	for p: Pickup in pickups:
		_put_vec2(buf, p.pos)
		buf.put_utf8_string(p.kind)
		buf.put_32(p.ttl)
	buf.put_u32(mines.size())
	for m: Mine in mines:
		_put_vec2(buf, m.pos)
		buf.put_32(m.arm_ticks)
	buf.put_32(mine_stock)
	buf.put_32(mine_cooldown)
	buf.put_32(overcharge_stacks)
	buf.put_u32(schematics_found.size())
	for s: String in schematics_found:
		buf.put_utf8_string(s)
	_put_vec2(buf, arena_size)
	buf.put_float(surf_line)
	return buf.data_array


func state_hash() -> int:
	return hash(serialize())


func _put_projectile(buf: StreamPeerBuffer, p: Projectile) -> void:
	_put_vec2(buf, p.pos)
	_put_vec2(buf, p.vel)
	buf.put_32(p.ttl)
	buf.put_32(p.damage)


func _put_vec2(buf: StreamPeerBuffer, v: Vector2) -> void:
	buf.put_float(v.x)
	buf.put_float(v.y)
