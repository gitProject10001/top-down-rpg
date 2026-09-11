extends Node
## THE ONE THING GODOT DOES NOT SHIP: whose turn it is to attack.
##
## Everything else about a coordinated pack is engine machinery. NavigationAgent3D paths, separates
## and flows around obstacles; its RVO avoidance keeps bodies out of each other; `avoidance_priority`
## makes the crowd part for whoever is committed. None of that needed writing. But no engine has an
## opinion about how many of five enemies may swing at once, and that single number is most of the
## difference between a pack and a scrum.
##
## TWO IDEAS, AND BOTH ARE OLD:
##   TOKENS   a small number of attack permits per target. Only a holder may enter S.ATTACK. This is
##            the "ticketing" pattern -- the reason a Death's Door or Hyper Light Drifter crowd
##            reads as taking turns rather than mobbing.
##   SLOTS    an angular ring around the target. Everyone waiting is given a bearing to wait ON, so
##            the pack encircles instead of forming a queue in the player's face.
##
## NO ENEMY GETS A NEW BRAIN. `enemy.gd` gains one gate (`and _claim_token()`) and one question
## (`_goal()`), and the emergence comes from those two answers interacting with tuning that already
## existed. A smart enemy in isolation becomes unfair when doubled; a simple one becomes interesting.
##
## THE OPT-IN IS THE AGENT, NOT THIS FILE. A body with no NavigationAgent3D child never calls
## report(), never appears in a ring, and is never asked for a token -- so a scene that does not opt
## in is not merely unaffected by this autoload, it never reaches it. That is what keeps the four
## player_vs_* benches running the enemy.gd that shipped.
##
## Debug: F5 (AiGraph) draws the ring, the slots and who holds a token.

## A body was given its turn. `target` is who it is for -- tokens are per-target, not global.
signal token_granted(enemy: Node, target: Node)
## ...and handed it back, however that happened. Fires for watchdog reclaims too.
signal token_released(enemy: Node, target: Node)
## The pack around `target` changed size and everyone was re-slotted.
signal ring_rebuilt(target: Node, slots: int)

@export_group("Tokens", "token_")
## HOW MANY MAY SWING AT ONCE. The single most important number in this file: 1 reads as a duel
## with spectators, 3 is already a scrum. 2 lets a second attack arrive while you are answering the
## first, which is pressure, without ever being unreadable.
@export var token_count := 2
## The watchdog deadline. MUST exceed the longest turn any body can take -- the brute's 2.6 s
## cooldown plus ~0.75 s of slam tween is ~3.4 s -- or a live attacker is yanked mid-swing.
@export var token_max_hold := 4.0
## How long a holder may be out of S.ATTACK, AFTER it has swung at least once, before its turn is
## reclaimed. Covers the cross-fade between a hit reaction and the swing resuming.
@export var token_grace := 0.25
## How long a body may hold a turn it has NOT yet spent -- the walk in from the ring. The brute is
## the sizing case: 1.58 m of ring-minus-reach at 2.2 m/s is 0.72 s, and it may be steered around
## a crowd on the way. A turn granted to a body that then loses its target is reclaimed here rather
## than being held for token_max_hold.
@export var token_approach := 2.5

@export_group("Ring", "ring_")
## Slot radius as a multiple of the body's own reach(). NOT a taste value: 1.35 is the multiplier
## the chase itself already uses to decide it has ground to make up, so a body sitting on its slot
## stands at exactly the distance its own AI calls "not yet in range". One number, two consumers.
@export var ring_margin := 1.35
## Floor, so a short-reach body still leaves the player room to swing.
@export var ring_min_radius := 2.5
## Debounce on reassignment, so a double kill does not make the whole pack change its mind twice.
@export var ring_reassign_every := 0.5
## A member that stops report()ing for this long is gone -- dead, freed, or disengaged. 0.2 s is
## 12 physics frames, which no live body can miss.
@export var ring_stale_after := 0.2

## THE A/B SWITCH, and it exists for the probe. "The pack encircles" is only a claim if you can
## measure the same fight without it; block F prints the angular spread both ways. A real off, too
## -- every token is handed back, so this cannot leave the fight jammed.
@export var enabled := true

## PRIORITY, THE WHOLE "CROWD PARTS FOR THE ATTACKER" BEHAVIOUR. RVO's rule is that an agent does
## not adjust its velocity for agents of LOWER priority, so a holder raised above its neighbours is
## steered around by all of them and yields to none. Two assignments, zero custom avoidance code.
##
## THE RESTING VALUE IS AUTHORED, NOT A CONSTANT HERE. Waiting priority is a per-archetype dial and
## belongs on the NavigationAgent3D in the scene, next to radius and neighbor_distance -- this file
## only borrows it for the duration of a turn and puts back whatever the scene said. Writing a
## constant back instead silently overrode scene authoring the first time a body released a token,
## and it showed up as the brute: a 0.95 m body on a 6.08 m ring has to cross the swordsmen's 3.24 m
## ring on every trip out, and at equal priority it is the one that yields. It spent a quarter of
## its waiting time jammed inside its own slam radius.
## The reason string for the one reclaim class that is NOT a bug. See _yank_reasons.
const YANK_APPROACH := "never reached the target"

const PRIORITY_HOLDER := 1.0
## Fallback only, for an agent whose scene forgot to state one.
const PRIORITY_WAITING := 0.35

## HOW FAR ALONG THE RING A BODY MAY AIM AT ONCE. The ring is a place to BE, but getting to it is
## the part that goes wrong: four bodies that arrive from the same side are assigned four bearings
## and three of them are on the far side of the player, so a body handed its slot as a POINT walks
## the straight line to it -- which passes through the target. Measured: waiting bodies closing to
## 1.64 m against a 3.24 m ring, 36% of their waiting frames inside their own strike band, and a
## worst case 5.11 m off the slot they were supposedly holding.
##
## So a waiting body is never given the far point. It is given a point on the ring a bounded step
## around from WHERE IT ALREADY IS, and it walks the circle. That is also simply what circling a
## target looks like, which is the behaviour the ring was for.
const ORBIT_STEP := deg_to_rad(40.0)


## One ring per target. A RefCounted class rather than nested Dictionaries because every field here
## is read each frame by the F5 overlay, and a typo in a string key is a silent null.
class Ring extends RefCounted:
	var target: Node3D
	var melee: Array[Node3D] = []        ## slotted, token-eligible
	var ranged: Array[Node3D] = []       ## counted and drawn; never slotted, never a holder
	var holders: Array[Node3D] = []
	var granted_at := {}                 ## instance_id -> seconds this turn began
	var used := {}                       ## instance_id -> it has entered S.ATTACK at least once
	## instance_id -> seconds it was FIRST seen out of S.ATTACK, cleared every frame it is in.
	## Not derivable from granted_at: see the grace test in _sweep_tokens for why that is the
	## whole difference between a watchdog and a hair trigger.
	var left_at := {}
	var seen_at := {}                    ## instance_id -> seconds; the staleness sweep's clock
	var angle_of := {}                   ## instance_id -> radians
	var dirty := true
	var next_assign := 0.0


var _rings := {}                         ## target instance_id -> Ring
var _t := 0.0
## Reclaims the watchdog made rather than a body handing its turn back. The probe FAILS on a
## non-zero count: a leak the safety net swallowed is still a leak, and this is the only place it
## is visible from outside.
## agent instance_id -> the avoidance_priority its SCENE authored, captured before we ever raise it.
var _base_priority := {}
var _watchdog_reclaims := 0
var _max_hold_seen := 0.0
## WHY the watchdog fired, not just how often, because the reasons mean OPPOSITE things.
##
##   "left ATTACK", "held", "freed"  -- a release path in enemy.gd did not run. A LEAK, and the
##                                      fight was rescued by its safety net. Must be zero.
##   "never reached the target"      -- a body was given a turn and could not close in time, so it
##                                      was handed to somebody better placed. THE WATCHDOG DOING
##                                      ITS JOB, and a normal event in a crowd.
## Counting them together made the first class invisible behind the second.
var _yank_reasons := {}
## Turns handed out, so an approach reclaim can be reported as a RATE rather than a bare count.
var _turns_granted := 0


# --- What enemy.gd calls -------------------------------------------------------------------

## TELL THE DIRECTOR WHAT IS TRUE NOW. Called every physics frame by every opted-in body, and it is
## deliberately the ONLY registration path -- there is no join/leave pair to forget.
##
## `_state = S.CHASE` is written at eleven sites in enemy.gd and three of them are inside tween
## lambdas; a register hook at each is eleven chances to leak a slot. Instead the director is simply
## told, and reconciles. A body that stops reporting -- dead (enemy.gd returns before this on DEAD),
## freed, or disengaged (`engaged` false) -- ages out of its ring on its own.
func report(enemy: Node3D, target: Node3D, engaged: bool) -> void:
	if not enabled or enemy == null or not is_instance_valid(target):
		return
	var r := _ring_for(target)
	var id := enemy.get_instance_id()
	if not engaged:
		# Disengaged is not merely "do not add": a body that de-aggroes or turns to flee while
		# holding a turn must give it back, or the cap is short one for the rest of the fight.
		_forget(r, enemy)
		return
	r.seen_at[id] = _t
	var list: Array[Node3D] = r.ranged if _is_ranged(enemy) else r.melee
	if not list.has(enemy):
		# The other list may hold it if a body ever changes attack_kind at runtime; cheap to be safe.
		r.melee.erase(enemy)
		r.ranged.erase(enemy)
		list.append(enemy)
		r.dirty = true


## ASK FOR A TURN. Idempotent, and false when the cap is full -- the caller simply does not attack
## this frame, keeps its cooldown at zero and asks again. Never queues: a queue would decide the
## order of a fight seconds before the player influences it.
func request_attack(enemy: Node3D, target: Node3D) -> bool:
	if not enabled:
		return true                      # a disabled director must not stop the fight
	if enemy == null or not is_instance_valid(target):
		return true
	var r := _ring_for(target)
	if r.holders.has(enemy):
		# ALREADY OUR TURN, AND THE CLOCK RESTARTS. A body whose cooldown is shorter than its own
		# recovery re-enters S.ATTACK on the frame after the last swing ended, without ever passing
		# through the release line -- so without this, one busy attacker accumulates hold time
		# across a run of swings and token_max_hold eventually yanks it mid-attack. The watchdog is
		# there for a STUCK holder, not a busy one.
		r.granted_at[enemy.get_instance_id()] = _t
		r.left_at.erase(enemy.get_instance_id())
		r.used.erase(enemy.get_instance_id())
		return true
	if _is_ranged(enemy):
		# RANGED NEVER TAKES A MELEE TURN. _chase_ranged already holds its own standoff band, and an
		# archer blocking a swordsman's turn from nine metres away is the cap doing the opposite of
		# its job. It is still counted in the ring for the overlay.
		return true
	if r.holders.size() >= token_count:
		return false
	r.holders.append(enemy)
	_turns_granted += 1
	r.granted_at[enemy.get_instance_id()] = _t
	_raise_priority(enemy)
	token_granted.emit(enemy, r.target)
	return true


## Hand a turn back. Safe to call when none is held -- enemy.gd calls it from _exit_tree and from
## _on_died without checking, because the paths that need it most are the ones that skip the checks.
func release_attack(enemy: Node3D) -> void:
	if enemy == null:
		return
	for key in _rings:
		var r: Ring = _rings[key]
		if r.holders.has(enemy):
			_hand_back(r, enemy)


## WHERE THIS BODY SHOULD WALK NEXT to be waiting properly -- a point ON the ring, at most
## ORBIT_STEP around from where it already stands, so the body circles the target instead of
## crossing it. Vector3.INF means "nowhere in particular", which is also every frame for a token
## holder, a ranged body, and every body in a scene with no director state.
func slot_for(enemy: Node3D) -> Vector3:
	var r := _ring_of(enemy)
	if r == null:
		return Vector3.INF
	var ang: float = r.angle_of.get(enemy.get_instance_id(), 1e9)
	if ang > 1e8:
		return Vector3.INF
	var c := r.target.global_position
	var cur := _bearing(r.target, enemy)
	# The bounded step is what makes this an orbit rather than a beeline. Signed and wrapped, so a
	# body always travels the SHORT way round to its bearing.
	var aim: float = cur + clampf(wrapf(ang - cur, -PI, PI), -ORBIT_STEP, ORBIT_STEP)
	var rad := _radius_of(enemy)
	return Vector3(c.x + cos(aim) * rad, enemy.global_position.y, c.z + sin(aim) * rad)


## The slot this body is ultimately headed for -- the ring position itself, not the next step
## toward it. For the overlay and the probe: drawing the intermediate aim would show a ring that
## appears to follow the bodies around instead of the bodies converging on it.
func assigned_slot(enemy: Node3D) -> Vector3:
	var r := _ring_of(enemy)
	if r == null:
		return Vector3.INF
	var ang: float = r.angle_of.get(enemy.get_instance_id(), 1e9)
	if ang > 1e8:
		return Vector3.INF
	var c := r.target.global_position
	var rad := _radius_of(enemy)
	return Vector3(c.x + cos(ang) * rad, enemy.global_position.y, c.z + sin(ang) * rad)


## RADIUS IS PER BODY, not one ring for the pack. A brute whose reach is 4.5 m waits at 6.08 m
## while a swordsman waits at 3.24 m, so the two never contend for the same bearing at the same
## distance -- and neither stands inside its own strike band doing nothing.
func _radius_of(enemy: Node3D) -> float:
	return maxf(ring_min_radius, _reach_of(enemy) * ring_margin)


## The ring this body is WAITING in, or null if it is not waiting in one.
func _ring_of(enemy: Node3D) -> Ring:
	if not enabled or enemy == null:
		return null
	for key in _rings:
		var r: Ring = _rings[key]
		if r.melee.has(enemy) and not r.holders.has(enemy) and is_instance_valid(r.target):
			return r
	return null


## DISABLED MEANS EVERYONE HOLDS A TURN, not that nobody does. request_attack() already answers
## true when arbitration is off -- so the two must agree, or a body is told it may swing by one
## call and told it is not swinging by the other. That disagreement is exactly what the A/B switch
## produced: with the director off every body cached a turn it did not have, and on switching back
## on it swung once more on a belief nothing backed.
func holds_token(enemy: Node3D) -> bool:
	if not enabled:
		return true
	for key in _rings:
		if (_rings[key] as Ring).holders.has(enemy):
			return true
	return false


# --- What the F5 overlay and the probe read ------------------------------------------------

## READ-ONLY, and a purpose-built API rather than get() on privates. ai_graph.gd reaches into
## enemy.gd's internals because enemy.gd is not ours to reshape for a debug panel; this file IS
## ours, so it can simply answer the question and stop pinning its own fields in place.
func snapshot(target: Node3D) -> Dictionary:
	if target == null or not _rings.has(target.get_instance_id()):
		return {}
	var r: Ring = _rings[target.get_instance_id()]
	var slots := {}
	for e in r.melee:
		if is_instance_valid(e):
			slots[e.name] = assigned_slot(e)
	return {
		"melee": r.melee.duplicate(),
		"ranged": r.ranged.duplicate(),
		"members": r.melee.size() + r.ranged.size(),
		"holders": r.holders.duplicate(),
		"cap": token_count,
		"slots": slots,
		"angle_of": r.angle_of.duplicate(),
		"next_assign": maxf(r.next_assign - _t, 0.0),
		"watchdog_reclaims": _watchdog_reclaims,
		"max_hold_seen": _max_hold_seen,
		"yank_reasons": _yank_reasons.duplicate(),
		"turns_granted": _turns_granted,
		"leak_reclaims": _leak_reclaims(),
		"approach_reclaims": int(_yank_reasons.get(YANK_APPROACH, 0)),
	}


# --- The tick ------------------------------------------------------------------------------

func _physics_process(delta: float) -> void:
	_t += delta
	if not enabled:
		_release_all()
		return
	for key in _rings.keys():
		var r: Ring = _rings[key]
		if not is_instance_valid(r.target):
			_drop_ring(key, r)
			continue
		_sweep_stale(r)
		_sweep_tokens(r)
		if r.dirty and _t >= r.next_assign:
			_assign(r)
			r.dirty = false
			r.next_assign = _t + ring_reassign_every
			ring_rebuilt.emit(r.target, r.melee.size())


## THREE WAYS A TURN COMES BACK WITHOUT ANYONE HANDING IT BACK, and all three have happened to
## somebody: the holder was freed, the holder left S.ATTACK and its own release line never ran, or
## the holder is simply stuck. A token that never returns is not a glitch -- it is a fight that
## STOPS, with four bodies standing on a ring waiting for a turn that will not come. So the director
## never trusts a holder to give it back; it only lets it be fast.
func _sweep_tokens(r: Ring) -> void:
	for i in range(r.holders.size() - 1, -1, -1):
		var h: Node3D = r.holders[i]
		if not is_instance_valid(h):
			r.holders.remove_at(i)
			_watchdog_reclaims += 1
			_note_yank("freed")
			continue
		var id := h.get_instance_id()
		var held: float = _t - float(r.granted_at.get(id, _t))
		_max_hold_seen = maxf(_max_hold_seen, held)
		if held > token_max_hold:
			_yank(r, i, h, "held %.1fs" % held)
			continue
		# GRACE IS MEASURED FROM LEAVING S.ATTACK, NOT FROM THE GRANT, and getting that wrong made
		# this watchdog fire on every successful attack in the game. `held` is already ~1.5 s by the
		# time a swordsman's swing finishes, so a test of `held > token_grace and not attacking`
		# is true on the very first frame after the clip ends -- one frame before the body's own
		# release line runs, because autoloads tick before scene nodes. Every clean attack looked
		# like a leak, and the counter that exists to expose real leaks reported eight of them.
		var st := int(h.get("_state"))
		if st == Enemy.S.ATTACK:
			r.used[id] = true
			r.left_at.erase(id)
		elif not r.used.has(id):
			# GRANTED BUT NOT YET SPENT: this body is still walking in from its ring, and "not
			# attacking" is true for that whole approach. Judging it by token_grace would reclaim
			# every turn before it could be used -- which is precisely what a slow body walking a
			# 1.58 m gap looks like from here.
			if held > token_approach:
				_yank(r, i, h, YANK_APPROACH)
		elif not r.left_at.has(id):
			r.left_at[id] = _t
		elif _t - float(r.left_at[id]) > token_grace:
			_yank(r, i, h, "left ATTACK for %s" % _state_name(st))


func _sweep_stale(r: Ring) -> void:
	for list in [r.melee, r.ranged]:
		for i in range(list.size() - 1, -1, -1):
			var e: Node3D = list[i]
			if not is_instance_valid(e) or _t - float(r.seen_at.get(e.get_instance_id(), _t)) \
					> ring_stale_after:
				if is_instance_valid(e):
					release_attack(e)
				else:
					_purge_holder(r, e)
				list.remove_at(i)
				r.dirty = true


## SLOTS, GREEDILY BY NEAREST BEARING.
##
## The ring is ANCHORED TO WHERE THE PACK ALREADY IS, not to world +Z. Pinned to an absolute
## bearing, a ring asks whoever happens to stand opposite it to run two radii THROUGH the player to
## reach slot 0 -- which is not a spread, it is a shuffle, and it reads as the AI changing its mind.
##
## Stable under shrinkage: when a member dies, n drops, the anchor is unchanged if the first member
## by name survives, and everyone's nearest slot is still about where they are standing. The pack
## widens its gaps rather than rotating.
func _assign(r: Ring) -> void:
	var members: Array[Node3D] = []
	for e in r.melee:
		if is_instance_valid(e):
			members.append(e)
	if members.is_empty():
		return
	# STABLE ORDER, BY NAME. instance_id is not reproducible across runs, and a probe that measures
	# an encirclement needs the same assignment twice. Hand-placed scenes have stable names.
	members.sort_custom(func(a, b): return String(a.name) < String(b.name))
	var n := members.size()
	var base := _bearing(r.target, members[0])
	var free: Array[int] = []
	for i in n:
		free.append(i)
	for e in members:
		var want := _bearing(r.target, e)
		var best := 0
		var best_d := TAU
		for i in free.size():
			var a: float = base + TAU * float(free[i]) / float(n)
			var d: float = absf(wrapf(a - want, -PI, PI))
			if d < best_d:
				best_d = d
				best = i
		r.angle_of[e.get_instance_id()] = base + TAU * float(free[best]) / float(n)
		free.remove_at(best)


# --- Plumbing ------------------------------------------------------------------------------

func _ring_for(target: Node3D) -> Ring:
	var id := target.get_instance_id()
	if not _rings.has(id):
		var r := Ring.new()
		r.target = target
		_rings[id] = r
	return _rings[id]


func _bearing(target: Node3D, e: Node3D) -> float:
	var to := e.global_position - target.global_position
	return atan2(to.z, to.x)


## The body's OWN reach, asked rather than re-derived. A ring computed from the exported
## attack_range while the body swings from a measured strike zone is a ring in the wrong place.
func _reach_of(e: Node3D) -> float:
	if e.has_method("reach"):
		return float(e.call("reach"))
	return 2.2


func _is_ranged(e: Node3D) -> bool:
	return int(e.get("attack_kind")) == Enemy.AttackKind.RANGED


func _agent_of(e: Node3D) -> NavigationAgent3D:
	if e != null and e.has_method("nav_agent"):
		return e.call("nav_agent") as NavigationAgent3D
	return null


## Raise this body above the crowd for the duration of its turn, remembering what the scene said.
func _raise_priority(e: Node3D) -> void:
	var a := _agent_of(e)
	if a == null:
		return
	var id := a.get_instance_id()
	if not _base_priority.has(id):
		_base_priority[id] = a.avoidance_priority
	a.avoidance_priority = PRIORITY_HOLDER


## ...and put back the authored value, not a constant. See the header note above PRIORITY_HOLDER.
func _restore_priority(e: Node3D) -> void:
	var a := _agent_of(e)
	if a == null:
		return
	a.avoidance_priority = float(_base_priority.get(a.get_instance_id(), PRIORITY_WAITING))


## What this body rests at, for anyone reporting on it.
func resting_priority(e: Node3D) -> float:
	var a := _agent_of(e)
	if a == null:
		return PRIORITY_WAITING
	return float(_base_priority.get(a.get_instance_id(), a.avoidance_priority))


func _hand_back(r: Ring, enemy: Node3D) -> void:
	r.holders.erase(enemy)
	r.granted_at.erase(enemy.get_instance_id())
	r.left_at.erase(enemy.get_instance_id())
	r.used.erase(enemy.get_instance_id())
	_restore_priority(enemy)
	token_released.emit(enemy, r.target)


func _state_name(st: int) -> String:
	var names := ["IDLE", "CHASE", "ATTACK", "FLINCH", "STAGGER", "DEAD", "FEAR"]
	return names[st] if st >= 0 and st < names.size() else str(st)


func _note_yank(why: String) -> void:
	_yank_reasons[why] = int(_yank_reasons.get(why, 0)) + 1


func _yank(r: Ring, i: int, h: Node3D, why: String) -> void:
	# COUNTED, because a leak the watchdog recovered is still a leak. The probe fails on this
	# counter being non-zero, which is the only way an enemy.gd release path that quietly stopped
	# working can be seen from outside -- the fight would look fine.
	_watchdog_reclaims += 1
	_note_yank(why)
	r.holders.remove_at(i)
	r.granted_at.erase(h.get_instance_id())
	r.left_at.erase(h.get_instance_id())
	r.used.erase(h.get_instance_id())
	_restore_priority(h)
	token_released.emit(h, r.target)


func _forget(r: Ring, enemy: Node3D) -> void:
	if r.holders.has(enemy):
		_hand_back(r, enemy)
	# Array.erase() returns void in Godot 4 (unlike Dictionary.erase(), which returns bool) — ask
	# first, then remove, or this is a parse error.
	if r.melee.has(enemy) or r.ranged.has(enemy):
		r.melee.erase(enemy)
		r.ranged.erase(enemy)
		r.dirty = true
	r.seen_at.erase(enemy.get_instance_id())
	r.angle_of.erase(enemy.get_instance_id())
	r.left_at.erase(enemy.get_instance_id())


func _purge_holder(r: Ring, e: Node3D) -> void:
	for i in range(r.holders.size() - 1, -1, -1):
		if r.holders[i] == e:
			r.holders.remove_at(i)


func _drop_ring(key: int, r: Ring) -> void:
	for h in r.holders:
		if is_instance_valid(h):
			_restore_priority(h)
			token_released.emit(h, r.target)
	_rings.erase(key)


func _release_all() -> void:
	for key in _rings.keys():
		var r: Ring = _rings[key]
		for i in range(r.holders.size() - 1, -1, -1):
			var h: Node3D = r.holders[i]
			if is_instance_valid(h):
				_hand_back(r, h)
			else:
				r.holders.remove_at(i)


## The probe's own reset, so a block that deliberately provokes a watchdog reclaim does not poison
## the assertion in the block after it.
## Reclaims that mean a release path in enemy.gd did not run -- everything except the approach
## deadline. This is the number that must be zero.
func _leak_reclaims() -> int:
	var n := 0
	for why in _yank_reasons:
		if why != YANK_APPROACH:
			n += int(_yank_reasons[why])
	return n


func reset_counters() -> void:
	_watchdog_reclaims = 0
	_max_hold_seen = 0.0
	_turns_granted = 0
	_yank_reasons.clear()
