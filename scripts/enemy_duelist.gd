class_name EnemyDuelist
extends Player
## THE MIRROR. An enemy that is not "like" the player but literally built from the player scene:
## same rig, same sword, same state machine, same measured attack envelope, same directional
## attack and directional guard. The only difference between the two fighters is which
## FighterIntent child is filling in the decisions.
##
## WHY NOT enemy.gd. That script is an excellent enemy and the wrong shape for this one. It chases
## on a distance check, telegraphs on a tween, and its damage window is a Call Method track keyed
## into a clip — none of which knows what a swing DIRECTION is, and all of which would have to
## learn. Worse, it would be a second implementation of the mechanic, and the whole point of a
## duel is that both sides are bound by one set of rules. Every other enemy in the project keeps
## using enemy.gd; this one is the player, with a brain.
##
## WHAT HAS TO CHANGE, and it is only four things, all of them identity rather than behaviour: the
## groups it answers to, the physics layers its hurtbox and hitbox use, and who it is looking for.
## Doing them in code rather than as inherited-scene property overrides keeps them in one readable
## place — the sword's HitBox in particular lives two instance levels down, where a scene override
## needs editable-children and is invisible to anyone reading the file.

## Physics layers, from sword.tscn and the player scenes: the player's HurtBox sits on layer 2 and
## enemy hitboxes mask it; every enemy's HurtBox sits on layer 4 and the player's sword masks that.
## Being a player body, this one starts on the player's side of both and has to swap.
const LAYER_PLAYER_HURT := 2
const LAYER_ENEMY_HURT := 4


func _ready() -> void:
	super()

	# GROUPS ARE THE PROJECT'S CROSS-CUTTING DISCOVERY, so this is what actually makes it an enemy:
	# the camera rig's lock-on, the HUD's boss bar and the player's own target acquisition all ask
	# the group, never the class. Done here rather than in the .tscn because an inherited scene
	# stores its root's group list wholesale, and a future re-parent of player3.tscn would silently
	# put this body back in the player group.
	remove_from_group("player")
	add_to_group("enemy")

	# Who it swings at. Player.acquire_target reads this; the human's copy stays "enemy".
	target_group = &"player"

	var hurt := get_node_or_null("HurtBox") as Area3D
	if hurt:
		hurt.collision_layer = LAYER_ENEMY_HURT
	if sword:
		var hitbox := sword.get_node_or_null("HitBox") as Area3D
		if hitbox:
			hitbox.collision_mask = LAYER_PLAYER_HURT

	# The hero's personal fill light travels with the hero. Two of them in one scene reads as a
	# lighting bug rather than as a second character.
	var light := get_node_or_null("HeroLight") as Light3D
	if light:
		light.visible = false


## Its own hurt radius, read by Player.hurt_radius_of when the other side sizes up a swing. The
## capsule lookup in that function already finds this body's HurtBox shape, so nothing is
## overridden here — the note exists because a reader will look for it.
