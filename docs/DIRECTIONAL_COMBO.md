# Directional tap combo

> **Historical directional-combat prototype.** This is not the current integrated player: see [MEADOW_COMBAT](MEADOW_COMBAT.md). Keep this document for legacy fixtures and AI-related mechanics; do not restore its controls by mistake.

The integrated player uses `DirAttack`. Three separate clicks now produce a finite
three-hit phrase. Default direction is right; unchanged input follows right, left,
overhead using the existing `atk_swing`, `atk_b`, and `atk_c` clips. A deliberate
direction change still selects that direction. Holding pauses at the windup apex;
release throws the blow, and a held direction change rewinds visibly as a feint.

| Step | Contact after starting | Active damage | Earliest next step / walking cancel | Dodge after | Forward step |
| --- | ---: | ---: | ---: | ---: | ---: |
| Opener | 150 ms | 100 ms | 295 ms | 275 ms | 0.28 m |
| Follow-up | 210 ms | 110 ms | 365 ms | 345 ms | 0.22 m |
| Finisher | 300 ms | 140 ms | 560 ms | 465 ms | 0.36 m |

These are the default unheld phrase's game-time values, rounded up to the next
physics frame. Hitstop and an intentional charge add elapsed time. Animation
playback uses the same per-action scale as these contact times. Other directions
can have slightly different lengths; a 360 ms floor keeps their poses readable.

- One press is buffered for 350 ms. The buffer stores one follow-up, not a queue
  of extra swings. Holding never repeats, and step three does not wrap.
- Dodge has a 200 ms buffer and wins over a queued follow-up once the active
  damage frames have finished. Guard can cancel preparation. Interruptions clear
  the chain, and a later attack starts again at step zero.
- Released steps use the current visible facing. They do not turn toward a target;
  side/back movement suppresses the forward step. Character collision resolves
  the actual movement. Existing 5-degree/10-cm early charge assistance remains.
- Only step two (zero-based) has the existing Sword finisher feedback and heavier
  shove. Shared enemy bodies use 80 ms damage immunity instead of the hero's
  500 ms, so a following valid contact is not silently absorbed.
- Legacy `FighterIntent` / `DuelBrain` keeps the original held attack cadence.
  The older bodies without `DirAttack` retain their existing `Attack` state.
- Dash and dash-attack buffers return to `DirAttack` when that state exists.

## Integration

`DirAttack.combo_index()` returns zero through two. Signals:

- `combo_step_started(index, direction, clip)` also fires when a feint rewinds.
- `damage_window_opened(index, duration)` fires when Sword becomes active.

Timing, hit windows, step distances, stamina costs and buffer duration are exposed
on `DirAttack`. The animation speed helper is per fighter and returns to 1.0 on
exit, so hurt, guard, dash and other bodies do not inherit the combo speed.

## Acceptance

`tools/check_directional_combo.gd` drives actual press/release events through
`PlayerIntent`, the real player scene, animation clock and swept-blade collision.
It checks clicks between frames, three distinct attacks/contacts, finisher tagging,
finite windows, held charge without repeat, buffered dodge/reset, late dash attack,
directional feint, guard cancellation, legacy intent, and enemy immunity/knockback.

The broad contact receiver intentionally isolates rhythm from enemy footwork.
The additional `--range-only` mode uses a normal 0.5 m radius / 1.3281 m high
capsule: all three real blade cuts connect from 1.3 m and 1.6 m, while an 8 m
target remains untouched and the total phrase travels less than 1.1 m.
Integrated encounters separately exercise enemy footwork, guard and retaliation.
