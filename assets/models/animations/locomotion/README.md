# Locked locomotion

Six already-retargeted animation resources reused from the sibling `rpg-3d/assets/models/animations` project (Mixamo sources). No models, textures or ogre solver imported. `aim_back/left/right` supply walking legs; `run_back` and `strafe_left/right` supply running legs. Existing UAL forward locomotion and upper-body sword stance remain local.

`locomotion_layers.gd` duplicates resources per actor, removes horizontal root drift, blends only humanoid hips/legs during lock, and creates recovery-step clips with the existing upper-body stance. Playback follows actual movement speed. Original resources remain unchanged.
