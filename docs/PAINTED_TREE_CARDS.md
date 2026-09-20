# Painted tree cards

The original branch and trunk meshes stay in place. Only the leaf mesh is replaced by deterministic sprays generated from the authored branch paths and crown ellipsoids. Each spray has six vertices and four triangles, a shallow central fold, and a drooping tip. Its long axis follows the nearest branch projected onto the leaf plane; it never follows the camera.

The renderer uses 70% crown normal and 30% card normal, per-lobe pigment variation, internal cavity weights, and wind fixed at the spray base. The original tree bounds constrain new vertices. The result has 1,350 sprays on broadleaf and 1,541 on pine, cached per species, source mesh, seed and normal blend.

## Integration

- Keep calling `canopy_shading.for_mesh(source_mesh, species)` for leaf meshes only.
- Bind `assets/textures/anime_painted/foliage_sprays.png` to `leaf_painting` in `anime_canopy.gdshader`.
- The atlas has compact / open / elongated / forked sprays in reading order. UV2 stores local spray coordinates; COLOR stores cavity / pigment variation / tip wind weight.
- Alpha scissor is 0.32; alpha-to-coverage edge is 0.20 and requires MSAA. This follows [Godot's spatial shader reference](https://docs.godotengine.org/en/4.6/tutorials/shaders/shader_reference/spatial_shader.html). Texture mipmaps are enabled.
- The sibling project's branch-oriented frame and folded-card approach was inspected as technical reference. No sibling code, model, image or mask was copied.

## Verification

Run `tools/check_anime_trees.gd` with the project Godot executable. It checks deterministic rebuilds, source and trunk preservation, bounds, fold geometry, four atlas cells, finite normalized normals and anchored wind. It renders eight azimuths at three orthographic sizes per species with actual D3D12 rendering into:

- `captures/anime_tree_broadleaf_8x3.png`
- `captures/anime_tree_pine_8x3.png`

Rows are near, gameplay-sized and distant; columns rotate by 45 degrees. These verify coverage and orientation, not that an illustration has been perfectly matched.

## Original atlas provenance

Generated using the built-in imagegen tool on 2026-09-19. Original output retained at `C:/Users/jonny/.codex/generated_images/01a0b97d-8c7e-7d10-bcf3-da4e48069c8f/exec-1291467e-9c41-4d09-984f-4feedf16091e.png`. Copied into the project without pixel edits; original alpha preserved.

### Generation prompt

Use case: stylized-concept. Asset type: one production RGBA foliage texture atlas for alpha-cut 3D tree cards in a hand-painted isometric game. Create ONE SQUARE atlas with four isolated leaf sprays on a genuinely transparent background, arranged in an exact 2 by 2 equal quadrant grid. There must be generous transparent padding of 12% within every quadrant; no leaves may cross a quadrant boundary. Top-left: COMPACT dense irregular spray of 16-22 leaves. Top-right: OPEN airy spray with gaps and 12-15 leaves. Bottom-left: ELONGATED thin spray with 14-18 leaves. Bottom-right: FORKED two-prong spray with 16-20 leaves. Every spray grows upward from a narrow base at bottom to tips at top, entire spray fully visible. Flat frontal view, NO cast shadow, NO backdrop, NO grid, NO labels or text. Leaves should be short asymmetrical broad brush dabs with slightly pointed tips, NOT round cabbage lettuce leaves. Japanese animation background gouache painting, clear readable brush shapes, muted sage olive green midtones and subtle warm ochre accents, limited subdued blue-green cool paint. Simple 2 or 3 pigment patches per leaf, opaque interiors, broken irregular painted silhouettes. Do NOT make shiny or photorealistic leaves, veins, tiny texture noise, grey outlines, distant scenery, pot, whole tree, or wood trunk. Overall albedo suitable for later dynamic lighting, avoid strong prebaked highlights or deep black shadows. Actual transparent alpha between leaves and around all four isolated sprays.
