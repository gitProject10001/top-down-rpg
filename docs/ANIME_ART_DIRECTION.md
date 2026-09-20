# Anime painted art study

Open `scenes/dev/integrated_landscape.tscn` and run the current scene (F6 in the editor).
The editor and runtime share the editable `ArtStudyLayers` profile. Select that node,
expand Profile, then use Regenerate art preview. The runtime starts painted; F7 switches between painted and original;
1 / 2 / 3 retain the city / river / lake teleports. The main game scene is unchanged.

For a static editor-visible river study, open `scenes/dev/anime_river_editor_preview.scn`.
It contains baked grass instances, real path pebbles, painted materials and the light rig.
Use the saved camera preview to inspect its framing. It is a generated visual snapshot,
not the playable scene; regenerate after art changes with the check command plus
`-- --river-only --export-editor-preview`.

## Camera FOV

Press **O** for the overview and again to return to gameplay. **F8** is the Godot
editor's Stop shortcut; it remains an overview alias only in standalone runs.
Use **Shift+F3** to hide/show debug drawing without changing the camera.
`tools/check_overview_camera.gd` exercises the full scene with the actual renderer
and SDFGI: six overview roundtrips at FOV 13°/0°, held-key echoes, restored framing
and following, plus the standalone F8 alias and separate debug shortcut. The final
run exited cleanly; logs are in `captures/overview_after.log`.

Open `scenes/dev/gameplay_preview_rig.tscn`, select **Pixel/View/IsoCam**, then use
**Framing → Perspective Fov** in the Inspector. The rig defaults to **13°**;
**0° selects orthographic projection**. The public slider runs from 0 to 40 degrees
and updates live in the editor and at runtime. Positive values below 1° supplied
from code use Godot's minimum valid perspective FOV of 1°.

FOV changes preserve pitch, yaw, focus and the scale at the focal plane.
`ortho_size` remains the visible height at that plane; camera distance is computed
as `height / (2 * tan(FOV / 2))`. At height 17.5 m, FOV 13° places the lens 76.798 m
from the focus, and 26° places it 37.900 m away. Larger FOV increases depth variation
and brings the camera closer without zooming the focal plane.

The optional **Shadow Light Path** points to `../Sun` in this rig. Its shadow range
follows the camera distance plus a visible-depth margin, never falling below the
sun's original range. Near-zero perspective also moves the clipping slab close to
the focus so shadow cascades do not waste their range in empty space. Editor saves
temporarily restore the authored sun range, then reapply the viewing range, so
repeated saves do not accumulate an inflated baseline.

The rig uses SDFGI vertical coverage of **100%**. This retains indirect shading
around the ground with the more distant 13° lens. The procedural sky remains part
of the lighting: replacing it with a flat background visibly weakens this shading.
Very small positive FOV values place the camera hundreds of metres away and can
exceed the fixed SDFGI coverage; use 0° for the orthographic endpoint.

Existing scenes retain their orthographic default. Legacy `perspective_enabled`
and `match_perspective_framing` fields remain hidden compatibility properties.
The camera's `@tool` preview avoids dialogue, combat and input processing in the
editor; gameplay following, lock framing and optional orbit remain intact.

`tools/check_camera_fov.gd` passes headless projection/unprojection tests at 0°, 13°
and 26°: a 4 m span on the focal plane stays **148.114 pixels** in a 1152×648
viewport, with unchanged center and angle. It also verifies near-zero input,
sun coverage, target following, lock/orbit behavior, Inspector fields, saved FOV
and the old orthographic scene.

Actual full-scene gameplay captures are `captures/elevation_gameplay_fov13.png`
and `captures/elevation_gameplay_fov0.png`, at visible height 17.5 m near the front
cliff. The 13° run on an RTX 3070, at an actual 1152×648 render size, measured
**GPU 5.796 ms median / 12.882 ms p95**, render CPU **0.662 / 0.740 ms**, and elapsed
frames **16.685 / 17.050 ms**. These are 120 samples after 180 warmup physics frames;
render CPU excludes gameplay, and elapsed frames include presentation waiting.
This local static-view sample is not an overall 60 fps guarantee while streaming
or moving. The paired orthographic run measured GPU **6.568 / 12.313 ms**.
Raw values are in `captures/elevation_gameplay_metrics.json`.

## Rendering

- `anime_art_direction.gd` keeps the original materials and lighting for an immediate A/B.
  Only the integrated scene opts in. Layout, architecture and trunks remain; leaf geometry
  is rebuilt inside the existing crowns and the two Affioramento guides have continuous cliffs.
- Castle masonry uses opt-in matte shading with no specular highlight, broad cool/warm pigment
  variation and irregular light paint marks. Original vertex colors, joints and geometry remain.
  The profile traverses generated internal nodes and surface materials; reveal/cutaway uniforms
  keep their original material objects. F7 restores the original shading branch.
- Meadow and path use new painted albedo textures with mipmaps, sampled as overlapping bounded
  crops to hide texture borders. Roads retain their authored control map.
- Submerged ground uses sandy paint instead of grass. Water preserves its existing flow,
  wave field, wakes and obstacle foam; the painted profile changes color and reflection scale.
- `anime_grass.gd` instances real blades in 8 m chunks around the player (or editor preview center). Density is deterministic;
  raycasts restrict grass to terrain, and road/water masks exclude paths and water.
  Roots are darker, blades receive world shadows, and vertex animation moves the tips.
  Blade shadow casting is disabled to avoid subpixel shadow-map stippling; SSAO and root
  gradients supply local contact shading.
- Grass derives twelve meshes in four families from `GRASSPIECE` in the user's Blender example:
  low compact (5 blades), medium leaning (4), tall sparse (3), and low swept (6).
  Only the source's six front ribbons are used with double-sided rendering; its reverse
  shell is excluded. Ribbons are widened laterally without lengthening their silhouettes.
  Individual blades differ in height, bend, rotation and root position. Seeded density and
  profile fields create irregular patches with mixed boundaries and open ground between them.
  Each ribbon also has independent width and a slight lateral tip hook. A separate small-scale
  pigment field groups cool-green and muted ochre strokes independently of tuft height;
  per-ribbon brightness varies only from 0.90 to 1.08 to limit visual noise.
  Base spacing is 0.12 m divided by the square root of profile density (default 1.3),
  with higher occupancy inside patches and sparse edge fill. A shared coverage map drives
  road blending, grass exclusion and local palette/density edits on terrain and scatter.
  Each instance varies its footprint independently of height. Patch density also controls
  cool root darkening and material AO, fading to unoccluded tips by 65% of blade height.
  Screen-space AO is explicitly enabled at 0.18 m radius and 1.05 intensity for local contact.
  Path margins use probabilistic grass coverage and a wider, irregular material blend.
  Small low-poly path pebbles cast shadows; water opacity fades across the shallow bank.
  The sun's 1.8 degree angular size softens character shadows.
  The source is exported to `assets/models/anime_grass/grass_piece.json`. Its `grass_normal.png` is exported
  unchanged as `assets/textures/anime_painted/grass_brush_normal.png`. Both grass and ground
  sample that painted world-space normal field at the source's 4.581 m scale. The grass light
  function groups illumination through a soft ramp instead of sharp per-blade diffuse contrast.
  Original source: `AnimeGrassTutorialVersion2a_Demo_Blender51.blend`, material `ground`.
  The original tutorial scene was retained. Shading, wind and scatter are native Godot.
- Foliage uses folded, branch-oriented sprays and four original painted atlas shapes. Normals
  blend 70% crown volume with 30% card plane; mipmaps and alpha-to-coverage control fine edges.
  Original trunks and crown bounds stay intact. F7 restores original leaf meshes and materials.
- Continuous cliffs are editable children of each Affioramento guide. Fractures are geometry;
  collision toggles inherit from roots so rebuilding hidden geometry cannot create invisible
  obstacles. Locked/modified/manually decorated old rocks are retained. Successful cliff
  rebuilds request a deferred profile refresh so weathering and local edits remain bound.

See `ART_STUDY_DATA.md` for Inspector controls and persistent edits, and
`PAINTED_TREE_CARDS.md` for tree construction, atlas generation and comparison renders.

## Validation

Run Godot with `--path . --script res://tools/check_anime_art_direction.gd` using a real renderer.
The check creates before/after river and city PNGs under `captures/`, verifies unchanged tree
source restoration, crown bounds, F7 restoration, player movement, twelve distinct grass meshes and their presence,
and live water updates, and reports GPU time. Append `-- --river-only` for the focused river check.

This is an editable art study. The concept remains the visual target; foliage detail,
shore transitions and architecture need further art direction to match its painted finish.

## Generated texture provenance

Built-in imagegen was used, with no external image API. Final assets:
`assets/textures/anime_painted/meadow.png`, `path.png` and `leaves.png`.

Meadow prompt:

> Create a production game albedo texture, a single square seamless tile of hand painted anime meadow grass for a Studio Ghibli inspired 3D isometric environment. Strictly overhead orthographic flat texture, no perspective, no horizon, no objects, no trees, no rocks, no flowers, no cast shadows, no lighting gradient, no text. Broad deliberate gouache brush strokes forming softly interlocking organic leaf-green, sage-green and warm yellow-green patches. Dominant medium fresh green, NOT olive brown. Roughly 40 to 60 broad visible brush strokes across width, sparse small tapered grass-like accents, many restful low-detail regions, painterly shapes with crisp broken paint edges rather than blurry clouds. Limited harmonious palette, modest value contrast, no white highlights, no black. Even diffuse albedo, no baked directional lighting. This will tile over a large meadow viewed at gameplay distance: cohesive color masses first, delicate grassy brush texture second. Fill entire square edge to edge, tileable edges.

Path prompt:

> Production game albedo texture. Single square full frame top-down flat seamless hand painted dirt path, anime background gouache style. Muted warm sandy ochre earth, broad irregular painterly strokes, sparse small flat painted beige and muted gray pebble clusters occupying under 15 percent, most surface calm low-contrast compacted soil. Soft broken brush edges and deliberate angular pigment shapes. No grass, no objects, no directional light or cast shadows, no perspective, no border, no text. Avoid photographic gravel, dense noise, high contrast, white stones. Color palette tan earth and warm stone, suitable alongside fresh green hand-painted meadow. About 40 broad brush marks across width, readable at game camera distance, modest saturation. Fill whole image with material, no path silhouette or surroundings.

Leaf prompt:

> A single small cluster of 14 to 20 overlapping broad stylized leaves for an anime hand-painted tree foliage alpha card, isolated on a genuinely transparent background. Production game texture. Roughly oval upright spray occupying central 75 percent, tapered at top and bottom. Leaves form connected dense little groups with some gaps, simple rounded diamond and oval shapes, irregular gouache edges, clear large readable silhouettes. Muted sage and forest-green midtones, soft warm green upper faces, cool teal-green lower faces, no white, no yellow-white highlights, no black. Flat diffuse hand-painted color, no cast shadow, no perspective, no branch or trunk or stems, no flowers, no ground, no text, no border. Keep individual leaves large and simple so at 32 pixels across the cluster remains readable. The main requirement is a clean ALPHA silhouette with connected leaf masses and transparent space around them. Do not draw many tiny needles or stippling.
