# ProceduralAnim

Skeletal animation with **no clips**. The walk, the run, the lean, the settle and the footfalls are
computed every frame from the creature's own measured proportions; only a handful of key poses are
authored, and those are data rather than baked curves.

Built for the 4 m ogre in `scenes/ogre.tscn`. The pieces are general; the tuning is not.

## Why bother

The ogre's rig arrived as a T-pose with no animation in it at all, so there was nothing to import.
That turned out to be the interesting constraint: a four-metre creature has to *read* as four
metres, and the usual way to get that — slow a human clip down — produces a human in treacle. Big
animals do not move like small ones played back slowly. They take **fewer, longer steps and spend
more of the cycle on the ground**, and that is a law rather than a preference.

So almost everything here is derived from one measured number, the hip height:

| | |
|---|---|
| Froude number | `Fr = v² / (g·L)` — the speed at which creatures of different size are comparable |
| Alexander's stride | `s = 2.3·L·Fr^0.3` — validated across animals; check it against a human (L 0.9, v 1.4) and it returns a 1.31 m stride at 2.1 steps/s, which is how people walk |
| Duty factor | `β ≈ 0.75 − 0.3√Fr`, floored at 0.5 so both feet are **never** off the ground at once — a four-metre creature with an aerial phase reads as a costume |

Rescale the creature and its motion rescales correctly, for free.

## The layer stack

Child order under the `Skeleton3D` **is** execution order, and this order is load-bearing:

| | | |
|---|---|---|
| 1 | `OgrePoseLayer` | blends the active key poses onto the rest pose |
| 2 | `OgreGaitLayer` | locomotion on top, backing off wherever a pose owns a bone |
| 3 | `OgreDynamicsLayer` | inertia — the upper body arrives late at whatever those two asked for |
| 4 | `OgreFootIk` | the world-space contact guarantee |
| 5 | `OgreArmIk` | hands onto the weapon; last, because its target rides the other hand |

The rule that generates it: **order by the strength of the guarantee — local-space embellishments
first, world-space guarantees last.** A planted foot is the strongest claim in the system, so it
gets nearly the last word.

`OgreSolver` owns all state and ticks from the body's `_physics_process`. The layers integrate
nothing, query nothing and remember nothing — `_process_modification()` gets no reliable delta and
runs at an arbitrary point in the frame, so a physics query from inside one is a coin flip.

## Feet do not skate, by construction

At touchdown the foot's world position is recorded, and for the whole of stance the IK target **is**
that stored point. The body moves over a stationary foot. Skate is impossible rather than merely
small — which is why it is worth doing this way round.

`scripts/dev/probe_ogre_gait.gd` measures the promise at six speeds and on a ramp. Current: skate
p99 **0.0001 m/s**, stride error under 0.3%.

## The addon boundary

Nothing under `addons/procedural_anim/` may reference the game. No `EventBus`, no `Fx`, no `HitBox`,
no scene paths. The solver resolves autoloads by node path and degrades to nothing when they are
absent, and hands results back through one signal:

```gdscript
signal action_event(what: StringName, at: Vector3)
```

The host decides what a beat means. `enemy.gd` opens a damage volume on `hit_open` and spawns a
telegraph disc on `slam_telegraph`; the solver knows about neither.

`plugin.gd` registers nothing — the classes come from `class_name`, enabled or not. The folder is
the unit, and the boundary is the point.

## Integrating a creature

The solver's entire input contract is three facts every `CharacterBody3D` already knows:

```gdscript
solver.tick(delta, velocity, is_on_floor(), visuals.rotation.y)
```

That is what made it possible to build and prove the animation against a keyboard-driven puppet and
then drop the AI in underneath without the animation code changing. `scripts/enemy.gd` does it in
about a dozen lines, all guarded by `if _solver:`, so no other enemy is affected.

## Authoring

`scenes/dev/enemy_procedural_animation_test.tscn` — **F4** opens the pose editor. A pose *is* a
keyframe; an `ActionSpec` is the timing and easing between keyframes, which is what a curve is.
There is no separate animation pipeline: pose, save, and the attacks use it.

Ten poses are needed. The editor names each one and says what it is for.
