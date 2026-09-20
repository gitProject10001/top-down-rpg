# Editable painted art data

The integrated scene uses one `ArtStudyLayers` controller and one `ArtStudyProfile`
for the editor preview and runtime. Select **ArtStudyLayers**, expand **Profile** in
the Inspector, edit its values, then use **Regenerate art preview**. The default is
`assets/art/default_art_study_profile.tres`. Full viewport painting brushes are deferred;
the saved data and local masks are available now.

## Profile and local edits

- Grass density starts at **1.3**. Four weights select low compact, medium leaning,
  tall sparse and low swept families; each family has three mesh variants.
- The palette contains **root, cool stroke, warm stroke** coefficients. Shader
  integration passes these as linear vectors; converting them through an sRGB
  color uniform again darkens the vegetation.
- Grass, surface weathering and continuous cliffs have independent enable flags.
  Moss, damp and damage amounts have separate controls.
- Each `ArtSurfaceEdit` stores a stable ID, target `NodePath`, local position,
  orientation, radius, signed intensity, seed, layer, lock and deleted state.
- Paths are relative to the controller's parent. Positions and orientations are
  local to the selected surface. Stamp **+Y points out of the surface**; XZ is its
  painted plane. Stamp depth is 30% of radius, preventing through-wall bleeding.
- A negative intensity erases that layer. Deleting a stroke retains its record as
  a tombstone. Regeneration does not remove tombstones or move locked edits.
  Generated scatter instances are disposable; authored edits are the source data.

`add_edit()` assigns missing IDs and deterministic seeds. `set_edit_deleted()`
respects locked records. Existing IDs, seeds and values survive regeneration and
resource save/load. The Inspector can explicitly unlock records.

## Integration contract

`ArtStudyLayers.regenerate()` initializes missing IDs and emits
`regeneration_requested(profile)`. The integrated driver rebuilds from the same
resource in both editor and runtime.

`profile.sample_layer(layer, surface_path, local_point, base_value)` evaluates
local masks on the CPU. Layers are grass density, grass palette, moss, damp and
damage, numbered 0–4. Contributions add to the supplied base, then clamp to 0–1.

`profile.pack_shader_edits(surface_path, surface_to_world)` returns a fixed
32-entry packet: `art_edit_count`, `art_edit_rows_x/y/z`, `art_edit_values`.
The rows transform a world point to the normalized stamp. Values contain signed
intensity, layer and seed. Deleted records are excluded; stable-ID ordering keeps
the packet reproducible. `art_edit_overflow` reports additional records and is a
CPU diagnostic, not a shader uniform. All records remain in the resource.

Resources are scene-local when instantiated from a saved scene. Code constructing
controllers with `.new()` should explicitly assign an independent profile copy
when edits must not be shared.

## Elevations behind cliff boundaries

The two integrated formations enable **Zona sopraelevata** on their
`ContinuousCliff` child. The same guide defines the front boundary and its free
passage corridor. The surface joins the rocky crest, extends into an upper meadow,
and descends through a ramp beyond the guide's end. Height, depth, ramp length,
base height and seed remain Inspector properties of this existing generator.
The original isolated-rock generator remains available.

The upper surface has real collision. Grass uses physical surface heights and the
same painted coverage map as the lower terrain; that map expands to cover the
plateaus. Existing trees keep their XZ positions and gain only the elevation
offset. F7 and disabling the cliffs layer restore their original heights. Manual
tree offsets survive regeneration; optional tree metadata `art_elevation_locked`
excludes a tree from automatic height projection.

When F7 hides an upper zone, a player standing there moves to its existing lower
passage, where the original scene still has ground. Toggling back restores the
upper position if the player has not walked away. Regenerating a higher plateau
also adjusts the player's feet to the new surface.

Upper-ground density and palette edits use the stable surface path
`Affioramento_0/ContinuousCliff` or `Affioramento_1/ContinuousCliff`, with positions
local to that node. `height_at_local(Vector2(x,z))` provides the generated surface
height, including the ramp, or `NAN` outside. These records use the same profile,
regeneration action and saved-edit format as all other surfaces.

Generated meshes and preview material bindings are disposable. Saving the editor
scene restores the authored tree positions and material properties before save,
then reapplies the preview; source data is not replaced by a static mesh export.

## Verification — 2026-09-19

Elevation checks added with the camera update:

- `tools/check_elevated_zone.gd`: exact crest joins, top/ramp height queries,
  physical capsule ascent, deterministic generation and scene roundtrip.
- `tools/check_elevation_scene.gd`: two actual zones, twelve collision probes,
  eleven existing trees rooted on the new surface, 4,230 sampled grass bases,
  real player ascent of 4.715 m, plateau movement, F7/F8 and manual tree offsets.
- The same check with `-- --f7-only`: safe comparison-mode transitions on both
  plateaus, cancellation after walking away, and live height changes while on the
  plateau or while viewing the original scene.
- With `-- --coverage-only`: a raised-surface edit beyond the old map bounds
  removes 3,231 of 3,239 instances in its test chunk; the center and nine interior
  probes read zero density. Eight fringe instances fall within the documented
  512-pixel control-map boundary tolerance. Palette, locks, IDs and deletion
  records survive regeneration. These focused checks exit successfully; Godot
  still emits its existing `PagedAllocator` cleanup warning on shutdown.
- `tools/check_cliff_profile.gd`: stable cliff-target moss edits, local/world stamp
  transforms, material isolation, regeneration and disabled-collider inheritance.
- `tools/check_camera_fov.gd`: focal-plane framing at 0/13/26 degrees, shadow range,
  near-zero FOV, saved settings and legacy orthographic scene behavior.

`tools/check_art_study_layers.gd` passes resource roundtrips, locked/deleted edit
preservation, deterministic seeds, signed erase masks, overflow reporting, and
matching CPU/shader coordinates for rotated, nonuniformly scaled walls.

`tools/check_painted_concept.gd` passes the full integrated scene, two regenerations
with local edits, exact source-mesh restoration with F7, twelve grass variants,
player movement on the river approach and live water. It saves/reopens a script-free
visual snapshot in `user://` and directly exercises the editor setup twice, checking
the shared profile, painted materials, grass and absence of duplicated helpers.
The final full run exited successfully with no engine warnings or errors.

Performance was sampled after 40 warmup physics frames over 120 rendered frames,
at **1152×648**, Forward+ D3D12, RTX 3070, with **48,077 grass instances** in the river
area, before the elevation/FOV update. These are one local run's measurements,
not a cross-machine performance target.

| Measurement | Median | 95th percentile |
| --- | ---: | ---: |
| Viewport render CPU | 0.527 ms | 0.590 ms |
| Viewport render GPU | 6.526 ms | 6.561 ms |
| Elapsed frame interval | 16.687 ms | 16.818 ms |

Render CPU excludes other gameplay work. Elapsed intervals include waiting and
vsync; they do not demonstrate available frame headroom. Raw results are in
`captures/painted_concept_metrics.json`.

Actual renders: `captures/painted_concept_river.png`,
`captures/painted_concept_castle.png`, and `captures/painted_concept_sample.png`.
The cliff sample includes the actual terrain edge; it is not a composited concept.
