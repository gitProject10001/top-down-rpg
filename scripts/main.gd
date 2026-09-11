extends Node3D
## Root of the playable scene (main.tscn).
##
## Right now it only HOSTS things set up in the editor: the moody WorldEnvironment,
## the sun, the greybox room, the player and the camera rig.
##
## Later (M4) this becomes the entry point that asks a WorldManager to stream zone
## scenes into the $World node and to place the player at the correct spawn marker.
## Kept intentionally empty for now so there is one obvious place for that to live.
