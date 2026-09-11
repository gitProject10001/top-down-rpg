OGRE BAKED CLIPS — what these files are and how to refine one

Each action .glb holds the rig, the mace (an animated reference node), and ONE animation:
the recorded motion, on the game's own clock, complete from rest to rest.
ogre_carry_reference_baked.glb is the rest stance by itself — the pose every clip must
start and end on.

BLENDER SETUP (or the timeline will look wrong): the clips are keyed at 60 fps and Blender
defaults to 24 fps with a 250-frame range. Set Scene fps to 60 BEFORE importing — the
importer maps seconds onto frames with the fps of that moment, so importing at 24 squeezes
an 83-frame clip onto 33 frames and no later fps change unsqueezes it. Then set the
timeline end to the frame count in the clip's .beats.txt. If the viewport plays the wrong
thing, pick the action in the Dope Sheet's Action Editor.

WHAT THE GAME USES from a refined clip: the upper body only — Hips rotation, spine, chest,
neck, head, shoulders, arms, hands. Everything else in these files is REFERENCE:
  - legs, feet and pelvis HEIGHT are solved live (foot planting, ground, crouch);
  - the mace is aimed live at the target (keep the hands near the reference shaft and the
    game's grip solve does the rest).

THE THREE RULES:
  1. First and last frame stay on the carry stance (match carry_reference). There is no
     runtime crossfade to hide a mismatch — the clip snaps on and off there.
  2. Keep the clip length. Beat times (see the .beats.txt next to each file) are the damage
     windows and telegraphs; they do not stretch with your curves.
  3. Interruptions (stagger, abandon) cut a clip mid-flight by design. Do not author for
     them.

THE ROUND TRIP: edit in Blender -> export -> import in Godot -> save the animation as
<action>.res -> drop it at assets/models/animations/ogre_clips/<action>.res -> run
tools/build_ogre_clips.gd. No code. Then run the four gates (docs/combat-refactor.md,
"The four gates").
