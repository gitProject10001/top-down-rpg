# SimWater

**A toolkit, not a solver.** Water in a game is several different problems wearing one word, and
they do not want the same machinery:

| the job | the tool | what it costs |
|---|---|---|
| a lake that sits there and takes ripples | the RIPPLE FIELD - a linear wave equation over a flat rest surface | almost nothing |
| water that fills, drains, floods, breaks on a shore, flows round a body | the SHALLOW-WATER SOLVER - depth over a bed, staggered, conservative | a CFL ceiling, a float16 store, a settling transient, and real care |

The point of the addon is that BOTH live here behind one driver and one surface, so a scene can use
the right one for its job and they draw the same way. A puzzle room with a rising flood wants the
solver. A decorative lake wants the ripple field. Neither wants the other's problems.

## What it does NOT know about

The solver is general purpose and must stay so. It knows about a bed, a water level and a spring -
three questions, on `SimTerrain` (`scripts/swe_terrain.gd`) - and nothing about tiers, painted maps,
regions, zones or any particular game. The GAME supplies an adapter that answers them; the shipped
one is `scripts/sim/swe_terrain_oracle.gd`, which is the only file in the project that knows both
sides.

Artistic and gameplay limits are the same story: they belong on top as policy, never inside. `Water`
caps how much of a column one splash may displace; `WaterLook` carries colour, clarity and foam;
`level_keep` pins a lake to its authored level because "the environment does not change on its own"
is a gameplay requirement and not a fluid one. The solver ships all of those OFF.

## Layout

    shaders/swe_sim.gdshader        the solver: both encodings, behind `depth_mode`
    shaders/water_surface.gdshader  the simulated surface, w = b + h
    shaders/swe_view.gdshader       false-colour debug views, for the bench
    scripts/ripple_field.gd         the driver (autoload `Ripples`): window, scroll, impulses
    scripts/water_window.gd         the surface mesh that follows the window
    scripts/swe_terrain.gd          the seam: bed_y, level_y, is_spring, present
    scripts/water_look.gd           appearance as data, per zone

## The rules that were paid for

- **One sim step per RENDERED frame**, never per physics tick. Physics ticks twice in a frame often
  enough, and both viewports then render in sibling order and the ping-pong silently drops a step.
- **Exactly one viewport may render per frame.** There is no MRT escape from a canvas_item shader;
  the leapfrog is one pass with redundant face recompute because of it.
- **The renderer must stand on the same lattice as the solver.** Every border artifact this water
  has ever had was the picture and the simulation disagreeing about WHERE something is, not about
  what it was.
