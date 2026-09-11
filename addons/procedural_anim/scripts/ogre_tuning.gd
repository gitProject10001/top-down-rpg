class_name OgreTuning
extends Resource
## Every dial the ogre's procedural animation has, in one Resource.
##
## WHY A RESOURCE AND NOT CONSTANTS. Two reasons, and the second is the real one:
##
##   1. `TuningPanel.from_object()` (scripts/dev/tuning_panel.gd) reads a property list and builds
##      the whole slider panel from it — correct bounds from @export_range, headers from
##      @export_group. Adding a dial here adds a slider to the lab, with no lab code at all. That
##      file's header states the rule: "Add a uniform, get a knob."
##   2. A tuned ogre is then a FILE, not a diff. You can save it, revert it, and see it in git as
##      readable text — the same treatment bonemap_mixamo.tres gets.
##
## NOT @tool. tuning_panel.gd's header records what @tool did to crypt_stone.tres: a script gained
## new @exports and the editor wrote its stale in-memory copy back over the tuned one. Nothing here
## needs to run in the editor, so nothing here is @tool, and the lab writes to disk only on an
## explicit keypress.
##
## THE NUMBERS ARE DERIVED, NOT DIALLED. Most of what makes the ogre feel heavy is not in this file
## — it falls out of the creature's measured leg length via the Froude number and Alexander's stride
## relation (see ogre_solver.gd). What lives here are the GAINS on top of those laws: how much of
## the physical prediction to actually use. A gain of 1.0 means "believe the physics"; the defaults
## sit near 1.0 for that reason, and a value far from it is a note that the law is being fought.

# ---------------------------------------------------------------------------------------------
@export_group("Gait")
## Stride length as a fraction of what Alexander's relation predicts. 1.0 = believe the physics.
## Below 1.0 the ogre shuffles — which is not automatically wrong for an ogre.
@export_range(0.4, 1.6, 0.01) var stride_gain := 1.0
## Cadence multiplier on top of stride. Raising BOTH makes it faster; raising only this makes it
## take the same steps more often, which reads as smaller. Weight lives in the ratio, not the speed.
@export_range(0.5, 1.8, 0.01) var cadence_gain := 1.0
## Extra time each foot stays planted, added to the duty factor the speed implies. Heavy animals
## keep their feet down longer than the Froude number alone predicts.
@export_range(-0.1, 0.25, 0.005) var duty_bias := 0.08
## The mass rule, and it is not negotiable: below 0.5 both feet leave the ground at once, and a 4 m
## creature with an aerial phase reads as a costume. Elephants never do it; neither does this.
@export_range(0.35, 0.7, 0.01) var duty_floor := 0.52
## How far apart the feet track, as a fraction of hip width. Heavy bipeds walk with a wide base.
@export_range(0.8, 2.5, 0.05) var stance_width := 1.35
## The crouch the ogre stands in even when it has room not to. A straight-legged giant reads as
## stilts; some permanent bend is most of what makes a heavy creature look like it is carrying
## itself. This is a FLOOR — the reach budget below will deepen it whenever the stride demands.
@export_range(0.0, 0.6, 0.005) var crouch_base := 0.12
## How far the pelvis may drop to buy stride. Past this the STRIDE is shortened instead.
##
## Keep this modest. Raised to 0.8 the solver will happily satisfy every foot-placement guarantee by
## squatting until its legs can reach the step the gait law asked for -- every number goes green and
## the ogre walks around on its haunches. A creature that cannot cover the ground takes smaller
## steps. This cap is what forces that answer instead of the other one.
@export_range(0.05, 1.2, 0.01) var crouch_max := 0.35
## Fraction of the leg's true length the gait is allowed to plan against.
##
## It MUST stay below TwoBoneIk.SOFT_REACH (0.98), and the gap between them is the whole point: the
## budget should run out BEFORE the IK's clamp does. Planned right up to the clamp, the hip bob and
## the footfall settle push the foot out of reach for the last third of every stance, the IK clamps,
## and the foot drags -- which looks exactly like the skate the plant lock exists to prevent.
@export_range(0.80, 0.97, 0.005) var reach_margin := 0.89
## Peak swing-foot clearance as a fraction of step length.
@export_range(0.02, 0.35, 0.005) var step_height := 0.12
## Where in the swing the foot reaches its highest point. Below 0.5 it snatches up and then FALLS,
## which is what heavy feet do — they are dropped, not placed.
@export_range(0.2, 0.8, 0.01) var step_apex := 0.38

# ---------------------------------------------------------------------------------------------
@export_group("Body")
## Fraction of the inverted pendulum's predicted hip rise actually used. The raw geometry gives a
## comical bounce because real knees absorb most of it; this is that absorption.
@export_range(0.0, 1.0, 0.01) var hip_bob_gain := 0.35
## Swing-side hip drop (Trendelenburg), degrees. Humans manage 4-7; a heavy pelvis drops further.
@export_range(0.0, 16.0, 0.25) var pelvis_list_deg := 9.0
## Pelvic rotation about the vertical, degrees. Long strides need it to reach.
@export_range(0.0, 20.0, 0.25) var pelvis_yaw_deg := 11.0
## How much the chest counter-rotates the pelvis. 0 = the torso turns with the hips, which reads as
## one rigid block on a stick.
@export_range(0.0, 1.2, 0.01) var spine_counter_gain := 0.7
## Seconds the chest lags behind the hips. THE LAG IS THE CUE — a heavy torso cannot turn on time,
## and inertia is only legible as lateness.
@export_range(0.0, 0.3, 0.005) var spine_lag := 0.08
## Shoulder swing amplitude at a full stride, degrees. Contralateral to the legs.
@export_range(0.0, 45.0, 0.5) var arm_swing_deg := 22.0
## Seconds the arms trail the legs. Long heavy arms hang back.
@export_range(0.0, 0.3, 0.005) var arm_lag := 0.08

# ---------------------------------------------------------------------------------------------
@export_group("Mass and inertia")
## Linear acceleration ceiling, m/s^2. g*tan(12 deg) = 2.09 is a heavy biped's comfortable lean, and
## it means roughly a second of runway to reach walking speed — and the same to stop. It commits.
@export_range(0.5, 12.0, 0.05) var max_accel := 2.1
## Turn rate ceiling in degrees/sec at walking speed. enemy.gd's usual smoothing is around 570 --
## about ten times too fast for this. If you change ONE number in this file, change this one:
## a slow turn is what makes flanking a readable mechanic instead of a stat.
@export_range(10.0, 360.0, 1.0) var yaw_rate_deg := 70.0
## Lean per unit of acceleration, as a fraction of the physically correct atan(a/g).
@export_range(0.0, 2.0, 0.01) var lean_gain := 1.0
## How much the neck cancels the body's lean. Animals keep their heads level; a body that leans
## under a head that does not is alive, and a block that rotates as one is a prop.
@export_range(0.0, 1.0, 0.01) var head_stabilise := 0.6

# ---------------------------------------------------------------------------------------------
@export_group("Springs")
## Hip vertical spring. Deliberately UNDERdamped (zeta well below 1): the overshoot after a footfall
## is the mass. Critically damped, the ogre lands like a hydraulic press.
@export_range(2.0, 30.0, 0.1) var hip_omega := 14.0
@export_range(0.1, 1.2, 0.01) var hip_zeta := 0.55
## Spine/chest spring — slower and looser than the hips, so the torso trails and settles last.
@export_range(2.0, 30.0, 0.1) var spine_omega := 9.0
@export_range(0.1, 1.2, 0.01) var spine_zeta := 0.35
## Downward kick fed into the hip spring on each footfall, m/s. Scaled by impact speed at runtime.
@export_range(0.0, 3.0, 0.01) var footfall_kick := 0.55

# ---------------------------------------------------------------------------------------------
@export_group("Upper body inertia")
## Overall responsiveness of the spine, shoulders, arms and head. BELOW 1 makes the upper body
## heavier and later; above 1 makes it snappier. This is the single dial that decides whether the
## ogre's torso reads as mass being moved or as a rig being posed.
@export_range(0.3, 2.5, 0.02) var upper_response := 1.0
## How much a carried weapon slows the arms, as a multiplier on their response. 1.0 = the mace is
## weightless, which is exactly how it looks.
@export_range(0.3, 1.0, 0.01) var weapon_drag := 0.65
## How fast the weapon swings to the aim a pose asks for. This is the arc of the swing itself, so it
## is the difference between a mace travelling and a mace cutting to its destination.
@export_range(2.0, 40.0, 0.5) var weapon_aim_speed := 13.0
## How far the head will turn to watch a target, degrees. Kept short on purpose -- a neck that can
## point anywhere reads as a turret rather than a creature.
@export_range(0.0, 90.0, 1.0) var look_yaw_deg := 52.0
@export_range(0.0, 60.0, 1.0) var look_pitch_deg := 26.0

# ---------------------------------------------------------------------------------------------
@export_group("Idle")
## Seconds per breath. Metabolic rate scales as mass^-0.26, and the ogre masses about eleven times
## a human, so it breathes roughly half as often — an elephant manages about six breaths a minute.
## Nobody consciously notices this. Everybody feels its absence.
@export_range(1.0, 14.0, 0.1) var breath_period := 7.5
@export_range(0.0, 0.12, 0.001) var breath_depth := 0.035
## Slow lateral weight shift while standing. A creature that stands perfectly still is furniture.
@export_range(0.0, 12.0, 0.1) var sway_period := 4.2
@export_range(0.0, 0.15, 0.001) var sway_amount := 0.045

# ---------------------------------------------------------------------------------------------
@export_group("Feedback")
## Camera shake per footfall, scaled by impact speed. Consumed by camera_rig.gd's existing
## EventBus.combat_impact handler — no new plumbing, and it is the loudest "four metres" cue there is.
@export_range(0.0, 0.5, 0.005) var footfall_shake := 0.0
## The impact a WALKING footfall produces. Only the part of an impact above this shakes the screen.
##
## Without it, walking shakes — continuously, about one and a half times a second, forever. A
## constant shake is not a cue; it stops carrying information within seconds and becomes something
## you notice only as fatigue. What should register is the DIFFERENCE between an ordinary step and a
## heavy one, so the ordinary step is what gets subtracted.
@export_range(0.0, 3.0, 0.05) var shake_floor := 0.7


## Size of the dust thrown up by a footfall, scaled by impact speed. Zero switches it off.
@export_range(0.0, 2.0, 0.02) var dust_scale := 0.55
## Distance at which a footfall stops being felt at all. Inside it the shake FALLS OFF with
## distance rather than being uniform: a hard cutoff means an ogre at 13 m rattles the camera
## exactly as hard as one standing over you and then stops dead at 14, which is both wrong and the
## reason walking felt so noisy across the arena.
@export_range(2.0, 40.0, 0.5) var shake_range := 14.0


## Yaw correction applied to an imported clip, in degrees, about the rig's own up axis.
##
## ZERO, and it must stay zero unless a clip genuinely needs turning. It was 180 for a while and
## that was a mistake worth leaving a warning about.
##
## The reasoning behind the 180 was that the ogre's scene puts a 180 degree yaw on its Model node,
## so the same yaw must land on the animation. It does not. The Model node rotates the whole
## subtree, mesh and skeleton together; a clip's tracks are bone-LOCAL rotations underneath that
## node, and they are already expressed in the frame the node rotates. Correcting them again turns
## the animation relative to the body it is playing on.
##
## What it actually did was spin the ogre's torso. Measured off the shoulder line, the body's facing
## against forward() ran +0.93 down to +0.15 and through -0.20 -- it was attacking with its back
## coming round. The symptom that led me to add it, a mace landing behind the ogre, was really the
## GRIP AXIS being wrong (see OgreSolver._measure_grip). Two errors that cancelled in the one
## measurement I checked, and did not cancel anywhere else.
@export_range(-180.0, 180.0, 5.0) var clip_yaw := 0.0


## How far up the haft from the BUTT the fist grips while a clip is driving the swing, in metres.
##
## The pose-authored placements grip 0.65 m up, which looks right standing still and is wrong the
## moment the mace is swung: a four-metre pole held 0.65 m from its end puts that 0.65 m of butt
## somewhere, and through the downswing "somewhere" is the ogre's own chest. Measured, the deepest
## intrusion sat at 0.00-0.35 m along the haft on every offending frame -- the stub, never the
## working length.
##
## Gripping at the butt is also just how a maul is held. Nothing behind the fist, nothing to bury.
@export_range(0.0, 1.2, 0.05) var clip_grip := 0.08


@export_group("The swing")
## The mace's angle from straight UP, in degrees, positive tipping forward. Carry is where it rests,
## wind-up is the coiled position over the shoulder. The STRIKE angle is not here: it is derived
## every frame from the pivot height, as whatever angle puts the head on the floor.
@export_range(-180.0, 180.0, 5.0) var swing_carry_deg := -4.0
## -28, not -52. At 52 degrees past vertical the head goes three metres BEHIND the ogre and five up,
## so the swing is more than 180 degrees of sweep and reads as a windmill. The arc wanted is a
## quarter-circle or so: coiled high and a little back, then over and down.
@export_range(-180.0, 180.0, 5.0) var swing_windup_deg := -104.0
## Fraction of the wind-up-to-strike time spent winding up. The remainder is the DELIVERY.
##
## THIS DIAL DOES TWO JOBS, and they are the same wish: it is also how long aim_tracking() keeps
## following the player. Raising it therefore makes the ogre adjust for LONGER after an early
## dodge and gives it LESS time to get the mace down — a late, snapped delivery instead of a
## long lean. On the slam (strike beat at 1.08 s) 0.75 spent 0.27 s on the descent, which read
## as the mace floating down; 0.85 spends 0.16 s, near the 0.15-0.2 s a heavy overhead wants.
##
## NO BEAT MOVES. The damage still opens at time_of(&"strike") and the telegraph is still the
## whole 0.95 s wind-up, so the player's reaction budget is untouched — only the weapon's speed
## profile inside it changes.
@export_range(0.3, 0.95, 0.01) var swing_wind_at := 0.85
## THE FOLLOW-THROUGH. A blow this heavy does not stop at the crater: the head carries PAST the
## landing angle while the momentum spends itself, and only then is hauled back to the carry.
## Degrees of overshoot beyond the landing point; 0 restores the dead stop.
@export_range(0.0, 60.0, 1.0) var swing_through_deg := 24.0
## Fraction of the recovery spent following through before the haul-back begins.
@export_range(0.05, 0.8, 0.01) var swing_through_at := 0.30
## THE COMMIT POINT. Before this fraction of the wind-up, a player who breaks the attack's band
## entirely (Zone.WRONG) cancels it — the ogre re-decides. Past it, the weight is moving: the
## blow finishes at the best reachable point and MISSES, and the miss is the opening. Without
## this the abandon window ran all the way to the strike, and running away a frame before
## delivery erased a fully-telegraphed attack — which read as the ogre flinching at nothing.
## 0.35, not 0.55: a third of the way into the wind-up is early enough that the ogre reads as
## having decided, and it sits well before the aim stops tracking (swing_wind_at, 0.85) — so
## the long middle of every wind-up is now COMMITTED BUT STILL ADJUSTING, which is the shape
## wanted: it will swing whatever you do, and it will swing at where you went.
@export_range(0.0, 1.0, 0.05) var commit_past := 0.35
## THE SHAPE OF THE WIND-UP IN TIME, in three pieces. A smoothstep from carry to the top is slow at
## both ends and quick in the middle, which puts the readable part of the telegraph in the wrong
## place: the mace moves fastest exactly when the player is trying to judge it, and there is no
## moment where it simply sits up there being a threat.
##
##   PREPARE   a quick set: feet, weight, the weapon coming off the shoulder. Short and brisk,
##             because nothing is being read yet -- it is the announcement.
##   RAISE     the long gradual climb. This is the telegraph, and it is most of the time.
##   AIM       held at the top. Time to see it, pick a direction and commit.
##
## swing_prepare is the fraction of the wind-up the quick set takes, swing_prepare_lift how far up it
## gets in that time, and swing_aim_hold the fraction spent held at the top before the smash.
@export_range(0.0, 0.6, 0.01) var swing_prepare := 0.18
@export_range(0.0, 1.0, 0.05) var swing_prepare_lift := 0.40
@export_range(0.0, 0.6, 0.01) var swing_aim_hold := 0.32
## Where the ogre's hands hold the haft through the swing: height above the feet at the top of the
## wind-up and at the moment of impact, and how far in front. The hands DROP as the mace comes down,
## which is both what a body does and what keeps the grip inside the arms' reach.
@export_range(1.0, 4.0, 0.05) var swing_high := 2.89
## (swing_low/swing_fwd/swing_back/swing_travel were deleted here: zero readers, and the 8-line
## doc below described a hands-travel mechanism that no longer exists. The lesson it recorded is
## kept because it cost a day:
##
## A weapon rotating about a fixed grip traces a circle, and a circle is what a swing looks like.
## Move the grip while it turns and the circle is dragged out of shape: with the hands descending
## 1.1 m as the shaft came over, the head rose, crossed the top, and then fell four metres in a
## straight vertical line -- because past horizontal, rotation about a descending pivot is almost
## pure descent. Plotted it was a column, not an arc.
## Tilt of the SWING PLANE off vertical, in degrees, toward the weapon side.
##
## At 0 the mace sweeps straight down the ogre's middle, which is a woodcutter's stroke and reads as
## symmetrical and dull. Tilting the plane takes it over the weapon shoulder and down across the
## body -- a diagonal, which is how anything is actually swung one-handed.
##
## There is a ceiling. The head only reaches the floor if the plane still has enough vertical in it:
## the vertical radius is (arm + haft) * cos(tilt), and that has to exceed the shoulder's height.
## Here that is 4.8 * cos(tilt) > 2.9, so beyond about 53 degrees the swing cannot reach the ground
## at all and _floor_angle clamps instead of solving.
@export_range(0.0, 60.0, 1.0) var swing_roll := 45.0
## How far off dead ahead a target can be and still get the straight overhead chop rather than a
## diagonal. Inside this the swing comes down the middle; outside it, in from whichever side the
## blow is going.
@export_range(0.0, 90.0, 5.0) var swing_centre_arc := 18.0
## Fraction of the arm's reach the grip may sit from the shoulders. Below 1 because an arm at full
## stretch is locked straight, and a locked arm reads as a mannequin rather than something braced.
@export_range(0.4, 1.0, 0.02) var swing_reach := 0.88
## Where the OFF hand grips, relative to the contact point, in metres along the haft. Negative is
## toward the butt, which is where a second hand goes on a two-hander.
## WHERE THE TWO HANDS GRIP THE MACE, as fractions of its length from the BUTT.
##
## Two points, deliberately far apart -- that is what makes a grip two-handed. The right hand sits
## near the butt for leverage and the left further up the haft to steer, which also leaves 7/8 of
## the weapon beyond the lower hand to reach with.
##
## Stated, not measured. Deriving them from the carry pose put BOTH hands at 1.965 m of 4.000 m --
## the same spot, so two points that were really one, gripping the middle of the haft with half the
## weapon sticking out behind the fists.
@export_range(0.0, 1.0, 0.005) var grip_right := 0.125
@export_range(0.0, 1.0, 0.005) var grip_left := 0.5
## How far the weapon may turn, in degrees, to bring the SECOND hand's grip within reach.
##
## The right hand is glued and does not move, so the only way to help the left one is to swing the
## shaft about that fist -- and the direction that helps is INBOARD, toward the far shoulder. That
## is a real cost: at 40 degrees the mace came across the chest and the ogre stood there hugging it,
## which is a worse pose than an idle second hand.
##
## So the budget is small, and the second hand is the thing that gives way. Where the grip can be
## reached with a nudge, both hands hold; where it would take hauling the weapon across the body,
## the left hand lets go and hangs, and the mace stays where the carry pose put it. The weapon's
## placement is not sacrificed to the second hand.
## MEASURED, at 18. --demo=carrysweep sweeps this against what it buys and what it costs, and the
## answer is a step rather than a curve:
##
##   cap    turn used   left palm off   shaft clear of the trunk
##   14        0.0         0.80 m            0.65 m      one-handed; mace held out
##   18       17.2         0.09 m            0.40 m      two-handed; mace 0.26 m closer in
##   34       17.2         0.09 m            0.41 m      no better, and no worse
##
## So the second hand costs 0.26 m of daylight between the shaft and the ogre, and nothing above 18
## buys anything at all -- the turn needed is 17.2 degrees and the rest of the budget goes unused.
## Set to the least that works: at 40 it had the same effect and merely looked like permission to
## haul the weapon further across the chest.
## Only 8, because the arm now does most of the work itself. With the clavicle free to swing
## (OgreArmIk.shoulder_assist) the turn the weapon has to make dropped from 17.2 degrees to 5.1, and
## the daylight between shaft and ogre came back from 0.40 m to 0.56. Reaching is the arm's job; the
## weapon moving to meet the hand is the last resort, not the first.
## 18, measured WHILE WALKING -- and the distinction matters more than the number. Swept on a
## stationary ogre this looked fine at 8; swept walking it is a cliff, and 8 was on the wrong side
## of it by four hundredths of a degree:
##
##   budget   grip lost   palm snap   elbow snap   shaft clear
##     8      131/240      22.1 m/s     23.4 m/s      0.53 m
##    12       91/240      20.4 m/s     23.3 m/s      0.54 m
##    16        0/240       3.9 m/s      4.0 m/s      0.54 m
##    26        0/240       6.3 m/s      4.9 m/s      0.53 m
##
## Note the last column: raising the budget costs NO clearance. The fear that a bigger yield would
## drag the mace across the chest was measured standing still, where the arm never leaves the one
## position that needed the least help.
@export_range(0.0, 90.0, 1.0) var grip_yield := 18.0
## Fraction of the arm's reach the second grip must come inside. Below 1 because an arm at full
## stretch is locked straight, and the grip IK fades out as it approaches the limit anyway.
@export_range(0.4, 1.0, 0.02) var grip_reach := 0.82
## How long every grip may be lost before the weapon is dropped, in seconds. A moment's slip while
## a hand crosses over is not letting go; a second of holding nothing is.
@export_range(0.0, 3.0, 0.05) var drop_after := 0.45
## The mace's mass once it is on the floor rather than in a fist. Four metres of iron.
@export_range(1.0, 400.0, 1.0) var weapon_mass := 120.0
## How much the walk cycle stops swinging an arm that is holding the weapon, 0 = swings as normal,
## 1 = perfectly still.
##
## An arm carrying four metres of iron does not swing like an empty one, and more to the point it
## must not: the gait swings the shoulder, the shoulder moving changes the distance to the haft, and
## the grip IK flips in and out of reach as it oscillates. Not a fight either side wins -- the hand
## simply never settles onto the weapon. Every other layer already yields where something else owns
## a bone; this is the same rule for the case where what owns it is an object.
@export_range(0.0, 1.0, 0.05) var arm_hold_calm := 0.85


@export_group("Aim")
## HOW FAST THE IMPACT POINT CHASES THE PLAYER WHILE THE OGRE IS AIMING, per second.
##
## Not glued to the player and not fixed in place: sprung, with lag. Glued and the blow is
## undodgeable; fixed and it is free to walk away from. Sprung, the player can see where it is going
## and has to move enough, early enough, to get out from under it.
@export_range(0.0, 20.0, 0.5) var aim_follow := 14.0
## How much of the target's own motion to lead by. 0 aims at where they are, 1 at where they will be
## when the blow lands. Short of 1 on purpose: a perfect lead cannot be beaten and reads as psychic.
@export_range(0.0, 1.5, 0.05) var aim_lead := 0.85
## How quickly the ogre believes a change in the target's direction. Low is sluggish and easy to
## juke; high makes it twitch at every sidestep.
@export_range(1.0, 30.0, 0.5) var aim_lead_smooth := 8.0
## How far out of band counts as "urgently out of band" for the shuffle.
@export_range(0.2, 6.0, 0.1) var aim_shuffle_span := 2.0
## How much faster the ogre may turn while it is aiming than while it is walking. Heavy things turn
## slowly, but a creature winding up to hit you is allowed to be trying.
@export_range(1.0, 5.0, 0.1) var aim_turn_boost := 2.6
## How much of the attack's lunge counts as reach the ogre has WITHOUT stepping -- how far the orange
## band extends in and out beyond the yellow one. At 0 the turn band is angular only, which leaves
## running straight at or away from the ogre as the cheap escape.
@export_range(0.0, 1.5, 0.05) var turn_reach := 0.9
## And how fast it chases once the smash has started. Near zero: the ogre is committed.
##
## This is the whole dodge window. Everything before the smash tracks, so standing still is fatal;
## the moment the mace starts down the point stops moving, so a dodge made THEN is clean. Dodge too
## early and the aim follows you; too late and you are already under it.
@export_range(0.0, 20.0, 0.1) var aim_follow_smash := 0.0
## HALF-ANGLE OF THE STRIKE WEDGE, in degrees either side of where the ogre faces.
##
## The one number in the zone system that is not derived, because it is not a reach limit -- it is a
## shoulder limit, and the reach maths knows nothing about shoulders. Beyond it the ogre would be
## swinging behind its own shoulder, which it cannot do and should not look like it is trying to.
##
## Outside the wedge is what TURNING is for. The zones are body-local, so they turn with it.
@export_range(10.0, 120.0, 1.0) var strike_yaw := 50.0
## The longest the wind-up may hang at the top waiting to be aligned, in seconds.
##
## A creature that has not finished turning should not swing anyway, and it should not wait forever
## either. Uncapped, this is an ogre that never commits; too short and the turn is pointless. It also
## makes the telegraph variable-length, which trades a memorisable rhythm for readability -- lower it
## if it reads as hesitation rather than menace.
@export_range(0.0, 2.5, 0.05) var aim_hold_max := 0.7
## How far beyond the strike zone the ogre will walk in, mace up, rather than give the attack up.
@export_range(0.0, 12.0, 0.5) var advance_max := 7.0
## How short and how long the arm may be made, as fractions of its full length, when adapting the
## swing to land on the impact point.
##
## THE IMPACT POINT IS THE RULER. The swing is solved backwards from where the blow has to land
## rather than the landing place being read off whatever the geometry did -- so gameplay leads and
## the animation follows it. What keeps that credible is that the only thing allowed to give is the
## arm: the ogre reaches out or draws in, which is what a creature does, and it is bounded, which is
## what stops it becoming a telescope.
##
## Distances outside what these afford are the shuffle's problem, and past that the attack is simply
## the wrong one for the range.
@export_range(0.2, 1.0, 0.02) var swing_arm_min := 0.40
@export_range(0.5, 1.4, 0.02) var swing_arm_max := 1.05
## Radius of the damage volume on the mace HEAD.
@export_range(0.1, 2.0, 0.05) var mace_hit_radius := 0.75
## Radius of the damage volume on the mace SHAFT -- the haft between the fists and the head.
##
## A four-metre two-hander whose only damage volume is a ball on the end is a lie the player can
## read: step inside the head and the swing passes through you. The haft is most of the weapon and
## it is moving fastest across the middle of the arc, so it gets a cylinder of its own. It rides the
## same HitBox as the head, which is what keeps one swing worth one hit -- HitBox clears its
## already-hit list per activation, so head and shaft cannot both bill you for the same blow.
##
## Sized like the head's: the dropped mace's haft collides at 0.16, and a damage volume runs a
## little generous over the visual so contact reads as contact.
@export_range(0.05, 1.0, 0.01) var mace_shaft_radius := 0.25
## Where the shaft starts hurting, as a fraction of the haft from the BUTT.
##
## 0.0 is the whole haft. The right fist sits at grip_right (0.125), so the default leaves the half
## metre of butt behind the hands live as well -- raise this past grip_right if a backswing catching
## someone standing behind the ogre reads as unfair rather than as a big creature with a big stick.
@export_range(0.0, 0.9, 0.005) var mace_shaft_from := 0.0
## How hard the ogre shuffles, in metres per second, to keep the player in the band it can hit from
## while it is aiming. Backing off when crowded, leaning in when the player drifts.
##
## A creature does not stand still winding up while its target walks inside its guard. This is the
## small correction that keeps a committed swing worth committing to -- and it only runs while
## aiming, so it cannot be used to chase someone down mid-blow.
@export_range(0.0, 6.0, 0.1) var aim_shuffle := 5.5


@export_group("Weapon clearance")
## Radius of the TRUNK the weapon shaft is not allowed inside, in metres.
##
## Deliberately narrower than the body's collision capsule (0.9 m). That capsule is sized for
## bumping into walls and it swallows the whole region an arm legitimately occupies -- measuring the
## shaft against it reports the mace as buried on every frame, including the ones that look fine,
## because a shaft starts at a hand and hands are attached to bodies. This is the visible trunk.
##
## Zero disables the correction entirely.
@export_range(0.0, 1.5, 0.02) var weapon_clear_radius := 0.62
## The trunk's extent above the feet: below the first is legs, above the second is head and neck.
@export_range(0.0, 3.0, 0.05) var weapon_clear_low := 1.15
@export_range(0.5, 4.0, 0.05) var weapon_clear_high := 3.05
## Distance over which the correction fades in as the shaft approaches. Without a band the push
## switches on the instant the shaft crosses the radius, and a correction that snaps on is a pop.
@export_range(0.02, 1.0, 0.02) var weapon_clear_margin := 0.30
## Length of shaft nearest the FIST that the correction ignores, in metres.
##
## Without it the constraint is unsatisfiable and thrashes. A hand holding something is often right
## against the body -- through this clip's recovery the ogre tucks its fist to its chest -- so the
## butt sits INSIDE the trunk, and no rotation about a point inside a volume will get a segment out
## of it. Asked to do the impossible, the correction swung the weapon 45 to 137 degrees a frame and
## still failed. Exempting the grip end asks the answerable question instead: never mind the fist,
## keep the LENGTH of the pole out of the ogre.
@export_range(0.0, 2.0, 0.05) var weapon_clear_skip := 0.75
## Hard ceiling on the correction, in degrees. The clearance solver is a safety net, not an
## animator: past this it is no longer keeping a weapon honest, it is throwing it around, and a mace
## that snaps to wherever the geometry is happiest stops reading as something heavy being carried.
## When it cannot win inside this budget it does what it can and lets the frame be imperfect.
@export_range(0.0, 90.0, 1.0) var weapon_clear_max := 12.0
## Fastest the weapon may turn, in degrees per second.
##
## The clip's own quickest motion is about 1100 deg/s, so this leaves the real swing alone and only
## catches the frames where something upstream tried to teleport the aim.
@export_range(200.0, 5000.0, 50.0) var weapon_turn_max := 1600.0


@export_group("Animation mix")
## HOW MUCH OF EACH PART OF THE BODY IS SOLVED RATHER THAN PLAYED, while a clip is running.
##
##   0 = the CLIP owns it outright        1 = the SOLVER owns it outright
##
## Between the two they are genuinely mixed, per group, every frame.
##
## WHY THIS IS HAND-BUILT. Unity does this with Animator layers and Avatar Masks; Godot's nearest
## equivalent is the filter on an AnimationNodeBlend2/Add2 inside an AnimationTree. Neither one
## helps here, because both blend a CLIP AGAINST A CLIP, on animation tracks. The procedural half of
## this system is not an Animation at all -- it is a SkeletonModifier3D stack that runs after the
## AnimationTree has already finished. There is nothing built in that can blend those two, in either
## engine, so the mask is ours.
##
## The groups are the ones worth arguing about separately. Arms and weapon default to the clip
## because the swing is the thing being imported; pelvis and legs keep real solver authority because
## they are the parts that answer to the ground.

## Neck and Head. Kept partly procedural so the ogre still tracks its target mid-swing.
@export_range(0.0, 1.0, 0.05) var mix_head := 0.4
## Spine, Chest, UpperChest.
@export_range(0.0, 1.0, 0.05) var mix_spine := 0.2
## Both shoulders, arms and hands -- AND the strength of the off-hand grip IK.
##
## At 0 the clip owns both arms and the IK lets go entirely. That is the fix for the off hand being
## dragged into the ogre's own chest: the IK was solving it onto the haft at full strength while the
## clip drove the same arm somewhere else, and nothing arbitrated. If a one-handed clip leaves the
## mace looking less two-handed than it should, about 0.3 is enough IK to keep the second hand near
## the haft while the clip still owns the swing.
@export_range(0.0, 1.0, 0.05) var mix_arms := 0.0
## Hips rotation, and how much of the clip's pelvis weight shift is taken.
@export_range(0.0, 1.0, 0.05) var mix_pelvis := 0.5
## How much of the clip's proposed STANCE the feet adopt. The foot IK still owns ground contact and
## plant locking at every setting -- this only decides how much of the authored brace is asked for.
##
## Not a second dial next to the old `clip_stance`: it IS that dial, inverted and renamed to match
## the rest of the group. Two names for one idea is how they drift apart.
@export_range(0.0, 1.0, 0.05) var mix_legs := 0.3
## The mace's ORIENTATION. At 0 it is rigid to the fist holding it; at 1 it takes the aim authored
## in the pose. Anything between slerps the two.
##
## Zero by default, and that is the bug fix: the weapon took its position from the hand and its
## rotation from the pose blend, which agreed only while poses drove the arm. Once a clip swung the
## hand through its own arc the two came apart and the shaft pointed where the fist was not.
@export_range(0.0, 1.0, 0.05) var mix_weapon := 0.0


## How far AHEAD OF THE BODY the shoulder has travelled by the time the mace lands.
##
## The ogre drives its whole trunk into a slam, so the hinge is not where it was when the swing
## started: measured, it moves from 0.22 m ahead of the body to 0.89 m. Predicting from the hinge's
## CURRENT position therefore promised a landing place 0.6 m short of the real one, every time, and
## drawing the strike zone from the body while solving it from the shoulder made the ring that much
## too small on top. One measured number fixes both, because both now ask the same question:
## where will the shoulder be when the blow arrives?
@export_range(0.0, 2.0, 0.01) var swing_lean := 0.89


## How much of an attack's shake belongs to the mace hitting the GROUND, the rest being kept for
## actually hitting someone. At 1.0 a whiff is as loud as a connect, which is where this started.
@export_range(0.0, 1.0, 0.05) var whiff_shake := 0.35


## How far round the horizontal sweep travels, each side of the aim. Wide enough that sidestepping
## does not answer it, which is the entire reason the attack exists.
@export_range(20.0, 180.0, 5.0) var sweep_arc := 95.0


@export_group("The kick")
## How high off the ground the foot is driven. Shin height on the target, not the ogre's own.
@export_range(0.4, 2.5, 0.05) var kick_height := 1.15
## How far the foot lifts off its plant before it goes forward. A heavy leg is hauled, not flicked.
@export_range(0.0, 1.5, 0.05) var kick_lift := 0.45
## The damage volume on the foot. Sized to a boot, the way mace_hit_radius is sized to the head.
@export_range(0.1, 1.5, 0.05) var kick_hit_radius := 0.55
## How much ground the kick's own step covers. Its band is quoted including this, because the band
## has to meet the swing's near edge or the ring between them is a place to stand and be ignored.
@export_range(0.0, 4.0, 0.1) var kick_lunge := 1.6
