class_name ActionSpec
extends RefCounted
## An attack expressed as data: which poses, in what order, and what fires when.
##
## THE SHAPE OF AN OGRE ATTACK is four beats, and the ratio between them is where the threat lives:
##
##   ANTICIPATION  slow, and it moves AWAY from the target. A heavy thing cannot be thrown forward
##                 without shifting the mass backward first, so the wind-up is Newton's third law
##                 made legible — and it is also the player's dodge window. enemy.gd already says
##                 this out loud: "the wind-up IS the telegraph".
##   STRIKE        four to five times faster than the wind-up. This is the whole trick; a strike
##                 that takes as long as its wind-up reads as a shove.
##   CONTACT       hitbox, hitstop, camera shake, hip drop, dust. All of it on one frame.
##   RECOVERY      long. The mace has swung past and has to be hauled back, and that is the punish
##                 window. Being generous here is what makes the fight readable.
##
## Actions never write bones. They write `pose_weights` and a handful of scalars on the solver, and
## the layers do the rest — the same intent / rules / detail split as the rest of the system, one
## level down. Adding an attack is a dictionary and two poses, with no new code path.

## A phase: which pose to blend toward, how long to take getting there, and how long to hold it.
## `ease` shapes the approach — "slow_in" accelerates into the next beat (a wind-up loading), "snap"
## arrives hard (a strike), "settle" decelerates (the follow-through).
class Phase:
	var pose: StringName
	var blend: float
	var hold: float
	var ease: String
	var event: StringName

	func _init(p: StringName, b: float, h := 0.0, e := "linear", ev := &"") -> void:
		pose = p
		blend = b
		hold = h
		ease = e
		event = ev

	func total() -> float:
		return blend + hold


var name_: StringName
## An authored clip for the UPPER BODY, played over the procedural everything-else. Optional: an
## action with no clip is driven entirely by its poses.
##
## The clip and the poses are not alternatives. The clip carries the arc -- the part that is a
## performance -- while the pose list still owns the timing, the planted feet, the root motion and
## the beats that fire the damage. See OgreClipLayer for why the split falls where it does.
var clip: Animation
## TRUE when `clip` is this action's OWN motion (baked from the solver, or hand-refined from that
## bake) rather than a borrowed human clip blended in by the mix dials. An authored clip owns
## every masked bone outright and plays on the identity mapping (clip time == action time); the
## legacy path underneath it — partial shares, a measured contact offset — exists for clips that
## were authored on some other body's clock.
var clip_authored := false
## Plays the clip at this fraction of its authored speed. A clip keyed for a human at human speed is
## not the tempo of something four metres tall.
var clip_speed := 1.0
## The moment IN THE CLIP at which the weapon lands, in seconds. The clip is offset so this instant
## falls exactly on the action's `strike` beat -- the one that opens the hitbox and detonates the
## telegraph disc.
##
## ALIGNED, NOT OFFSET BY HAND. The first version carried a start offset chosen by eye, and it was
## wrong: on the frame the ground was supposed to break, the mace was still up beside the ogre's
## head. Anchoring the two clocks at the contact frame instead means retuning the wind-up cannot
## slide the animation out of step with the damage, because both are measured from the same instant.
##
## Measured, not guessed -- step the clip with everything else frozen and find where the weapon hand
## bottoms out: `--demo=clipsweep` in the lab prints the sweep and names the frame.
var clip_contact := 0.0
## THE MACE LEADS. The weapon's path is authored and the ARMS are solved onto it, instead of the
## weapon hanging off a hand and going wherever the animation sends it.
##
## Right whenever the weapon's PATH is the point -- which for a slam it is, because the weapon is
## what carries the hit volume and what has to reach the ground. Implying that arc through shoulder
## angles is fighting the tool, and it lost: driven from the fist, the mace missed the floor by
## three metres, swung through the ogre's own chest, and could not be corrected without shoving it
## around so hard it stopped reading as something heavy.
var mace_leads := false
## The band, in metres, in which this attack can actually be delivered. Inside the near edge the
## weapon has no room and outside the far edge it does not reach.
var reach_min := 2.0
var reach_max := 5.0
## Is this something the ogre CHOOSES at a distance, as opposed to something that happens to it
## (stagger, flinch) or one step of a sequence (rock_lift)? Only these are ever switched to.
var is_attack := false
## Does this attack's range come from the solver's derived strike zone rather than from the two
## numbers below? True for the mace swing, whose reach is the arm's business and not a guess.
var use_strike_zone := false
## Which foot drives this attack, or -1 for none. The foot IK releases it and follows an arc.
var kick_foot := -1
## How high off the ground the blow arrives. 0 is the floor -- an overhead that craters. Anything
## above it is a flat stroke at that height, which a player in the air is above: this is the whole
## implementation of "jump to dodge the sweep", and it is physical rather than a rule.
var strike_height := 0.0
## Does the head travel HORIZONTALLY at that height, on a cone about the vertical, rather than
## swinging down through a plane to arrive there? A sweep needs this; an overhead must not have it.
var flat_sweep := false
## Does the damage come from the RING on the ground rather than from the weapon? The slam's disc is
## a warning and the mace is the weapon; the pound has no weapon contact at all -- the mace goes
## into the floor -- so for it the ring IS the attack. Without this the pound was a telegraph with
## nothing behind it: it fired, it shook the screen, and it could not hurt anyone.
var damage_from_ring := false
## This action finishes even from Zone.WRONG — the one zone that normally cancels. For a throw
## the weight is already aloft: cancelling mid-wind put the rock BACK in the hand, and a held
## rock chains rock_throw on every recover, so a player who hugged the ogre could veto the
## punish window for an entire fight (measured at 0.00 s over a full probe run). Committed
## actions release at the best reachable point and miss, and the miss is the opening — the
## same doctrine REPOSITION's out-of-patience branch already applies.
var commits := false
## Extra shove applied to whatever it hits. The kick's entire purpose is this number -- it is what
## puts you back out at mace range, and it is what makes spacing the SUBJECT of the fight rather
## than a side effect of it.
var knockback := 0.0
## What this attack may flow into when it ends, and how often. Weighted; empty means it ends in
## neutral. Strings are what turn a set of attacks into a fight you have to read.
var chains := {}
## ONE-HANDED. The off hand does not grip during this action; it is free to do whatever the pose and
## the gait ask of it.
##
## Not a limitation -- a choice about the move. Asking a second hand to stay on a haft that is
## travelling through a metre-and-a-half arc constrains the whole swing to wherever both arms can
## reach at once, and what it buys is one more hand on the weapon. This lets the mace go where the
## swing wants it.
var one_handed := false
var phases: Array[Phase] = []
## Metres of root motion, applied as a VELOCITY REQUEST the body consumes rather than a teleport.
## Negative in the wind-up (the weight shift back), positive on the strike (the lunge).
var root_motion: Dictionary = {}          ## phase index -> metres along the ogre's forward
## Both feet lock and the gait phase freezes for these phases. A slam happens with the feet PLANTED,
## and the planted feet are most of what makes it heavy — the legs stretch as the body drives
## through the swing instead of walking out from under it.
var planted: Array[int] = []
## Seconds into the action when the damage volume opens, and for how long.
var hit_at := 0.0
var hit_for := 0.16
## What the world does on contact.
var shake := 0.6
var hitstop := 0.09
var hip_drop := 0.18
var dust := 1.4
## Ground slam: spawn scenes/fx/area_attack.tscn at the impact point with this radius. Zero = none.
var slam_radius := 0.0
var damage := 3


func duration() -> float:
	var t := 0.0
	for p in phases:
		t += p.total()
	return t


## Seconds from the start of the action to the beginning of the named phase event.
func time_of(ev: StringName) -> float:
	var t := 0.0
	for p in phases:
		if p.event == ev:
			return t + p.blend
		t += p.total()
	return t


# =================================================================================================
# THE OGRE'S MOVES
# =================================================================================================

## THE TWO-HANDED OVERHEAD SLAM. Haul the mace up and back over the shoulder, drive it down through
## the floor, and leave a shockwave where it lands.
##
## 0.62 s of wind-up against a 0.13 s strike — nearly 5:1. Both feet are planted from the moment the
## mace goes up, so the ogre commits: it cannot chase you once it has started, which is what makes
## stepping aside a real answer instead of a reflex test.
## THE SWEEP — the mace swung flat, at the height of a person.
##
## The answer to it is to JUMP, and that is not a special rule bolted on: the head genuinely travels
## at waist height and a player who is in the air is above it. `strike_height` is the whole
## mechanism — the arc already solves a plane through the point it has to reach, so aiming that
## point a metre off the ground instead of at the floor produces a horizontal stroke for free, and
## the hitbox that misses a jumping player is the same one you can watch pass underneath them.
##
## It exists because the slam cannot answer someone circling: an overhead comes down on a SPOT, and
## a spot is easy not to be standing on. A flat swing covers an arc instead, so sidestepping does
## not work and the read is a different one.
static func sweep() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"sweep"
	a.is_attack = true
	a.mace_leads = true
	a.one_handed = true
	a.reach_min = 2.5
	a.reach_max = 4.5
	# WAIST HEIGHT. High enough that standing in it is fatal, low enough that a jump clears it.
	a.strike_height = 1.05
	a.flat_sweep = true
	a.phases = [
		# The quick one, and now genuinely quick: 0.52 s to impact against the slam's 0.72. It is
		# the answer to a player who has learned to walk out of the overhead, so it has to arrive
		# inside the time that walk takes.
		Phase.new(&"slam_windup", 0.28, 0.14, "slow_in", &"telegraph"),
		Phase.new(&"slam_strike", 0.10, 0.03, "snap", &"strike"),
		Phase.new(&"slam_recover", 0.18, 0.24, "settle", &"recover"),
		Phase.new(&"", 0.35, 0.0, "settle"),
	]
	a.root_motion = {1: 0.9}
	a.planted = [1, 2]
	a.hit_at = a.time_of(&"strike")
	a.hit_for = 0.16
	a.shake = 0.7
	a.hitstop = 0.10
	a.hip_drop = 0.16
	a.dust = 0.9
	a.damage = 2
	return a


## THE BACKSTEP — how a heavy creature refuses to be a punchbag.
##
## Not an attack and not a block: it is the ogre making ROOM. Your swings hit air, which costs you
## tempo rather than health, and then it is at the range its mace works at and you are not. That is
## the loop the fight was missing — there was previously no reason for the ogre ever to stop
## standing exactly where you could reach it.
##
## Short and cheap on purpose. A long one reads as fleeing.
static func backstep() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"backstep"
	a.is_attack = false                               # never CHOSEN by range; triggered by crowding
	a.phases = [
		Phase.new(&"kick_windup", 0.10, 0.02, "snap", &"telegraph"),
		Phase.new(&"carry", 0.22, 0.10, "settle", &"recover"),
	]
	# The hop. Backwards, and hard enough to leave a sword's reach in one move.
	a.root_motion = {0: -3.4, 1: -1.2}
	a.hit_at = 999.0
	a.shake = 0.2
	a.dust = 0.7
	# It does not end in neutral. It ends in a sweep, which is why crowding the ogre is PUNISHED
	# rather than merely undone.
	a.chains = {&"sweep": 1.0}
	return a


## THE POUND — both hands into the floor, and a ring that leaves.
##
## The answer is to run OUT, radially, which is the one answer neither the slam nor the sweep asks
## for. It also does not need to aim: it punishes being close without the ogre having to solve where
## "close" is, which is exactly the case the mace is worst at.
static func pound() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"pound"
	a.is_attack = true
	a.mace_leads = true
	a.reach_min = 0.0
	a.reach_max = 2.6
	# RETIMED TO THE HUNTER SKILL CLIP: the weapon-raised-high hold is the telegraph, the ring
	# detonates on the descent's bottom (clip contact 2.95; the skin's speed-1 window starts
	# the clip a second in, at the pull-back, so the raise and the drop both survive). The
	# strike blend matches the clip's 0.35 s descent so the beat and the visual arrive
	# together. A first cut held the full 2.6 s reach-and-raise as windup and it MEASURED
	# wrong: at a 0..2.6 m band the provoking player breaks range long before a telegraph
	# that long lands — abandons quadrupled and the punish window starved to zero.
	a.phases = [
		# Still the longest read in the fight - it is the one you answer by LEAVING, and running
		# out of a 2.6 m ring takes longer than stepping aside - but 1.95 s was three dodges deep.
		Phase.new(&"slam_windup", 0.80, 0.15, "slow_in", &"telegraph"),
		Phase.new(&"slam_strike", 0.30, 0.04, "snap", &"strike"),
		Phase.new(&"slam_recover", 0.20, 0.30, "settle", &"recover"),
		Phase.new(&"", 0.45, 0.0, "settle"),
	]
	a.planted = [0, 1, 2]
	a.hit_at = a.time_of(&"strike")
	a.hit_for = 0.14
	# The RING is the attack, so it carries the damage rather than the mace head does.
	a.slam_radius = 2.6
	a.damage_from_ring = true
	a.shake = 0.8
	a.hitstop = 0.09
	a.hip_drop = 0.34
	a.dust = 2.4
	a.damage = 1
	return a


## THE CHARGE — it commits to a straight line and cannot turn.
##
## The answer is to step sideways, and the reason it exists is that running away in a straight line
## was the strongest option in the fight: the ogre walks at 2.24 m/s against a player who runs at
## 6.0, so disengaging was simply free. This does not fix that by making the ogre faster — it stays
## slow, which is correct for something this heavy. It fixes it by making the straight line the
## dangerous place to be.
static func charge() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"charge"
	# RETIRED FROM THE MOVESET, same verdict as the kick: fully procedural, read as illegible
	# beside the pack's clips, and nothing in the pack runs. The far game is now the rock
	# throw (skinned with the firing clip); without a rock in range the ogre closes on foot.
	a.is_attack = false
	a.reach_min = 4.6
	a.reach_max = 12.0
	a.strike_height = 1.4
	a.phases = [
		Phase.new(&"slam_windup", 0.50, 0.26, "slow_in", &"telegraph"),
		Phase.new(&"kick_strike", 0.55, 0.05, "snap", &"strike"),
		Phase.new(&"slam_recover", 0.26, 0.34, "settle", &"recover"),
		Phase.new(&"", 0.50, 0.0, "settle"),
	]
	# The run itself, and it is committed — the solver stops steering once it is moving.
	a.root_motion = {0: -0.3, 1: 7.5}
	a.hit_at = a.time_of(&"telegraph")
	a.hit_for = 0.62
	a.shake = 0.75
	a.hitstop = 0.11
	a.hip_drop = 0.2
	a.dust = 1.4
	a.damage = 2
	a.knockback = 9.0
	a.chains = {&"slam": 0.6}
	return a


## THE SHORT ANSWER, for a player standing inside the mace's minimum reach.
##
## The slam has a hole in the middle of it -- the ogre cannot swing at something in its own
## footprint -- and before this the answer to a player in that hole was to abandon the attack and
## walk backwards, which is neither threatening nor readable. A kick fills the hole with something
## that has the same shape as every other attack here: a long anticipation, a fast strike, a beat
## that opens the damage, and a volume that has to actually overlap you.
##
## Faster than the slam on purpose. It is the punish for being too close, and if it telegraphed as
## long as the mace does, standing inside the ogre's guard would be the safest place on the map.
static func kick() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"kick"
	# RETIRED FROM THE MOVESET (is_attack false, and the crowd branch stopped naming it): the
	# procedural kick read as illegible next to the pack's authored performances, and the pack
	# has no kick to skin it with. The spec survives because the solver's kick machinery
	# (hitbox, arc, zone) still compiles against it and the probes still assert that machinery
	# stays DEAD. Crowding is now answered by the backstep alone, whose sweep chain carries
	# the punish the shove used to.
	a.is_attack = false
	# Its band is derived too, from the LEG rather than the arm -- see OgreSolver.zone_for().
	a.kick_foot = 1                                   # the right foot
	a.phases = [
		Phase.new(&"kick_windup", 0.34, 0.10, "slow_in", &"telegraph"),
		Phase.new(&"kick_strike", 0.11, 0.04, "snap", &"strike"),
		Phase.new(&"kick_windup", 0.20, 0.12, "settle", &"recover"),
		Phase.new(&"", 0.40, 0.0, "settle"),
	]
	# The planting foot stays planted; the other one is the attack. Freezing the gait phase for the
	# whole action is what keeps the ogre standing on one leg instead of trying to walk on it.
	a.planted = [0, 1, 2]
	# IT STEPS INTO IT. A kick delivered from a standstill reaches as far as a leg, which leaves a
	# band between the leg and the mace that nothing covers -- and standing in it was the safest
	# place on the map. The lunge is what closes that band, and it is why kick_zone() is allowed to
	# quote a reach longer than the leg.
	a.root_motion = {0: -0.15, 1: 1.60}
	a.hit_at = a.time_of(&"strike")
	a.hit_for = 0.22
	a.shake = 0.5
	a.hitstop = 0.07
	a.hip_drop = 0.14
	a.dust = 0.8
	# CHIP. The kick's job is to move you, not to kill you -- it is the shove that resets spacing,
	# and it costs a quarter of your health so that being shoved is a warning rather than a defeat.
	a.damage = 1
	# THE SHOVE, and it matters more than the damage. You end up back at the range the mace works
	# at, which is the loop: close, take your window, get put out, read the next one, close again.
	# FAR ENOUGH TO MATTER. Twelve carried the player about three quarters of a metre once friction
	# had it, which is a nudge -- they were back inside sword range before the ogre had finished the
	# animation. The shove has to cross the mace's minimum reach or it has not done its job.
	a.knockback = 22.0
	return a


static func slam(clip: Animation = null) -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"slam"
	# Mixamo's downward attack, retargeted. 2.27 s of human-tempo swing slowed to suit a creature
	# this size, and started a little in so its wind-up does not idle before the ogre commits.
	a.clip = clip
	# Near real time. The weight does not come from slowing the clip down -- a slowed human reads as
	# a human in treacle -- it comes from the dynamics springs lagging the chest behind the arms and
	# from the ogre's own stride law underneath.
	a.clip_speed = 1.0
	# Measured by --demo=clipsweep: the hand rises to 3.88 m at t=0.80 and bottoms at t=1.13.
	a.clip_contact = 1.133
	a.mace_leads = true
	a.one_handed = true
	# The band is the ARM'S, taken from the solver's strike zone. The 2.2..5.0 that used to be here
	# disagreed with the geometry by more than a factor of two.
	a.use_strike_zone = true
	a.is_attack = true
	a.phases = [
		# LONGER, because the wind-up IS the telegraph and it was only a fifth of the action. The
		# swing spends this time climbing slowly and then holding at the top -- see OgreTuning's
		# swing_prepare / swing_aim_hold for the shape inside it -- and a player needs that time to
		# read the direction and commit to a dodge. The strike stays as short as it was, so the
		# anticipation-to-strike ratio goes from about 4:1 to nearer 6:1.
		# TIMED AGAINST THE PLAYER'S DODGE, which is the only clock that matters here. The dash
		# covers 2.30 m in 0.18 s and comes round again every 0.5 s (dash.gd, player.gd), so a
		# 1.08 s time-to-impact handed out TWO dodges per swing and the ogre read as slow against
		# a target that is twice its top speed. 0.72 s is one dodge's worth: still twice the
		# 340 ms reaction floor the probe pins, and the 0.60 s telegraph is still the longest
		# read in the fight.
		Phase.new(&"slam_windup", 0.40, 0.20, "slow_in", &"telegraph"),
		Phase.new(&"slam_strike", 0.12, 0.03, "snap", &"strike"),
		Phase.new(&"slam_recover", 0.20, 0.30, "settle", &"recover"),
		Phase.new(&"", 0.40, 0.0, "settle"),
	]
	# THE LUNGE, and it is the answer to backing off. The ogre commits its aim and then drives its
	# weight forward into the blow, so a player who breaks range on the strike beat is still caught.
	# It is not a tracking increase -- the impact point is frozen by then and cannot follow you -- it
	# is the creature covering ground it decided to cover, which is readable and can be baited.
	a.root_motion = {0: -0.35, 1: 2.30}
	# PLANTED FROM THE STRIKE, NOT FROM THE START. Freezing the gait for the whole action was what
	# made breaking the ogre's range so easy: it could turn its yaw but its feet were nailed down for
	# the entire telegraph, so it slid, and walking out of the zone beat the attack every time. The
	# wind-up is now free -- the gait takes real little steps as the body turns and shuffles -- and
	# the feet plant on the strike, which is where planted feet were selling the weight anyway.
	a.planted = [1, 2]
	# DERIVED FROM THE STRIKE BEAT, never typed in. It was 0.68 s, which was right when the action
	# was shorter -- and then the wind-up was lengthened to make the telegraph readable and nobody
	# moved this. The strike now lands at about 1.08 s, so the damage volume was switching on four
	# tenths of a second EARLY, while the mace was still travelling upward: the ogre could hit you
	# with a weapon that was over its own head.
	#
	# Tied to the beat, that cannot happen again. Retune the wind-up all you like; the damage window
	# is always the moment of contact.
	# OPEN AT THE BEAT, not before it. A lead time is the wrong idea here: the smash is so fast that
	# even 60 ms early the head is still two thirds of the way up and three metres in the air, so a
	# window that "starts just before contact" starts with the weapon over the ogre's own head.
	#
	# It can afford to be generous now, because the damage is a real overlap between the mace's
	# volume and a hurtbox rather than a timer. An open window with the mace nowhere near you does
	# nothing at all; it only matters that the volume is live while the head is down where it landed.
	a.hit_at = a.time_of(&"strike")
	# SHORTER THAN THE DODGE THAT HAS TO SURVIVE IT. This was 0.35 s against a dash carrying 0.223 s
	# of i-frames -- the window was longer than the invulnerability, so rolling THROUGH a slam was
	# not possible and the only reliable answer was to stand outside its band. Souls runs 66-133 ms
	# of active hitbox against 433 ms of i-frames, a forgiveness factor of 3-6x; this is 0.15 s
	# against 0.223, which is the right side of 1.
	a.hit_for = 0.15
	a.shake = 1.0
	a.hitstop = 0.12
	a.hip_drop = 0.30
	a.dust = 2.1
	# THE SIZE OF WHAT ACTUALLY HITS YOU. It was 4.6 m -- a disc wider than the ogre is tall, for a
	# blow delivered by a head half a metre across. The damage now comes from the mace itself, so the
	# telegraph's job is to say WHERE that head is going to land, and a circle that does not match
	# the thing it is warning about is not a warning, it is a lie about the size of the attack.
	a.slam_radius = 0.95
	# THREE OF THESE KILL YOU, out of five hit points. The overhead is the attack the whole fight is
	# built to teach, so it has to be worth learning; two would make it a nuisance and four an
	# execution. It also finally does anything at all -- until the damage field was wired through it
	# dealt HitBox's default 1, the same as being brushed by a foot.
	a.damage = 2
	return a


## PICK UP A ROCK. Not an attack, but it uses the same machinery, and giving it a real duration is
## what stops the ogre teleporting boulders into its hand.
static func rock_lift() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"rock_lift"
	a.phases = [
		Phase.new(&"rock_lift", 0.38, 0.10, "slow_in", &"telegraph"),
		Phase.new(&"rock_lift", 0.02, 0.12, "snap", &"strike"),      # the grab
		Phase.new(&"carry", 0.40, 0.0, "settle", &"recover"),
	]
	a.planted = [0, 1]
	a.hit_at = 999.0                # nothing to damage
	a.shake = 0.0
	a.hitstop = 0.0
	a.hip_drop = 0.0
	a.dust = 0.0
	return a


## THROW THE ROCK. A rotation, not a push: the torso winds one way and unwinds through the release,
## which is why the wind-up pose yaws the spine hard.
static func rock_throw() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"rock_throw"
	# The long answer: nothing to swing at from out here, so it throws.
	a.reach_min = 5.0
	a.reach_max = 16.0
	a.is_attack = true
	# The HUNTER FIRING clip's whip window, at double speed (the skin's numbers). A slow
	# 1.95 s wind was tried first and it DEADLOCKED the fight: the probe's mobile player
	# broke range before the release beat, the abandon cancelled the throw with the rock
	# still in hand, and a held rock chains rock_throw on every recover — so the punish
	# window could never open again. The release has to beat the abandon.
	a.phases = [
		Phase.new(&"throw_windup", 0.55, 0.15, "slow_in", &"telegraph"),
		Phase.new(&"throw_release", 0.20, 0.02, "snap", &"strike"),
		Phase.new(&"", 0.60, 0.0, "settle", &"recover"),
	]
	# The rock is aloft: this throw HAPPENS, wherever the player has got to. See `commits`.
	a.commits = true
	a.root_motion = {0: -0.20}
	a.planted = [0, 1]
	a.hit_at = 999.0                # the rock does the damage, not the ogre
	a.shake = 0.25
	a.hitstop = 0.0
	a.hip_drop = 0.06
	a.dust = 0.0
	return a


## A ROAR. No damage, pure theatre and a fear pulse — but it reads as an ogre and it buys the fight
## a beat of rhythm between the slams.
static func roar() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"roar"
	# NOT is_attack, and that is deliberate rather than the old omission. Setting it made the roar
	# choosable and it promptly won a third of the picks, because it reaches everywhere and deals
	# nothing -- an ogre standing in front of you bellowing instead of swinging. A rest beat has to
	# be TIMED, not rolled: the point of it is one near-zero-threat moment every twenty or thirty
	# seconds, and something that turns up at random is not a rhythm. Enemy drives it on a clock.
	a.reach_min = 0.0
	a.reach_max = 14.0
	a.phases = [
		Phase.new(&"roar", 0.35, 0.55, "slow_in", &"telegraph"),
		Phase.new(&"", 0.50, 0.0, "settle", &"recover"),
	]
	a.planted = [0]
	a.hit_at = 999.0
	a.shake = 0.45
	a.hitstop = 0.0
	a.hip_drop = 0.0
	a.dust = 0.35
	return a


## The hit reaction, played as an action so it interrupts cleanly through the same path.
static func stagger() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"stagger"
	a.phases = [
		Phase.new(&"stagger", 0.10, 0.30, "snap"),
		Phase.new(&"", 0.55, 0.0, "settle", &"recover"),
	]
	a.hit_at = 999.0
	a.shake = 0.0
	a.hitstop = 0.0
	a.hip_drop = 0.12
	a.dust = 0.0
	return a


static func flinch() -> ActionSpec:
	var a := ActionSpec.new()
	a.name_ = &"flinch"
	a.phases = [
		Phase.new(&"flinch", 0.06, 0.08, "snap"),
		Phase.new(&"", 0.26, 0.0, "settle"),
	]
	a.hit_at = 999.0
	a.shake = 0.0
	a.hitstop = 0.0
	a.hip_drop = 0.05
	a.dust = 0.0
	return a


## THE HUNTER SKIN — the bought pack's clips (assets/models/animations/hunter/, in the library
## as hunter_*) laid over the gameplay-tuned beats. Explicit per action: which clip, the
## measured contact instant IN THE CLIP (tools/probe_clip_contact.gd — the hand's whip-and-
## bottom for an attack, start-anchored for a reaction), and the speed that lays the clip's
## window over the action's. The runner maps clip time as contact + (t − strike)·speed, so
## these three numbers are the whole alignment; beats, reach, damage and the weapon arc stay
## exactly as tuned — the arm IK re-solves gripping hands onto the live mace, so the clip is
## the PERFORMANCE (torso, head, legs, off-arm), never the geometry.
##
## Reactions have no strike event, so time_of(&"strike") is the action's full duration; each
## contact/speed pair below is chosen to make clip time 0 land on action time 0 exactly.
const HUNTER_SKIN := {
	&"slam": {&"clip": &"hunter_atk01", &"contact": 0.87, &"speed": 1.2},
	&"sweep": {&"clip": &"hunter_atk03", &"contact": 1.13, &"speed": 1.45},
	&"stagger": {&"clip": &"hunter_dmg_b", &"contact": 1.0, &"speed": 1.05},
	&"flinch": {&"clip": &"hunter_dmg_f", &"contact": 0.5, &"speed": 1.25},
	# The skill: reach, pull back, weapon raised high and HELD, then down — retimed pound
	# phases make that raise the ring's long telegraph, contact on the final descent's bottom.
	&"pound": {&"clip": &"hunter_skill01", &"contact": 2.95, &"speed": 1.55},
	# One throw clip, two actions: the lift plays the gather-and-grab window (hand reaches
	# low ~0.9), the throw starts mid-gather and releases at the 10 m/s whip (2.65).
	&"rock_lift": {&"clip": &"hunter_firing", &"contact": 0.9, &"speed": 1.0},
	&"rock_throw": {&"clip": &"hunter_firing", &"contact": 2.65, &"speed": 2.0},
}


## Every move the ogre has, by name.
## `clips` maps an action name to a borrowed (legacy) animation, blended by the mix dials — the
## slam's Mixamo clip goes through here with its measured contact offset. `authored` maps an
## action name to the action's OWN clip (baked from the solver, or refined from that bake in
## Blender); those play at full ownership on the identity mapping, and they win over `clips`
## where both name the same action. Anything in neither stays fully procedural — and the
## HUNTER_SKIN wins over everything, where its clip exists in the library.
static func library(clips := {}, authored := {}) -> Dictionary:
	var specs := {
		&"slam": slam(clips.get(&"slam")),
		&"kick": kick(),
		&"sweep": sweep(),
		&"pound": pound(),
		&"charge": charge(),
		&"backstep": backstep(),
		&"rock_lift": rock_lift(),
		&"rock_throw": rock_throw(),
		&"roar": roar(),
		&"stagger": stagger(),
		&"flinch": flinch(),
	}
	for n in authored:
		var a: ActionSpec = specs.get(n)
		if a == null or authored[n] == null:
			continue
		a.clip = authored[n]
		a.clip_authored = true
		a.clip_speed = 1.0
		# THE IDENTITY ANCHOR. The runner maps clip time as
		#   contact + (action_t - time_of(strike)) * speed
		# so contact == time_of(strike) makes clip time equal action time EXACTLY, for every
		# action — including ones with no strike event, because the two time_of() calls cancel
		# whatever value they agree on. A baked clip was recorded on the action's own clock, so
		# the identity mapping is the correct one by construction, holds included.
		a.clip_contact = a.time_of(&"strike")
	# The skin last, so it wins over the identity wiring — and falls away gracefully: delete
	# the hunter clips and the actions land back on their own bakes above.
	for n in HUNTER_SKIN:
		var a: ActionSpec = specs.get(n)
		var skin: Dictionary = HUNTER_SKIN[n]
		var c: Animation = authored.get(skin[&"clip"])
		if a == null or c == null:
			continue
		a.clip = c
		a.clip_authored = true
		a.clip_speed = skin[&"speed"]
		a.clip_contact = skin[&"contact"]
	return specs
