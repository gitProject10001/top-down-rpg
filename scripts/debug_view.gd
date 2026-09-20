extends Node
## Autoload "Dbg" — in-game debug toggles.
##
##   F3  combat volumes: HitBoxes (damage dealers) red — dim when idle, BRIGHT while the damage
##       window is actually live, which is the sync truth — and HurtBoxes (receivers) green. The
##       meshes are built by hitbox.gd / hurtbox.gd; this owns the flag and the hotkey.
##   Shift+F3  CLEAN VIEW: hide every non-gameplay thing at once.

var show_hitboxes := false

## THE MASTER SWITCH behind Shift+F3. F8 belongs to the editor's Stop command.
##
## Debug views accumulate — volumes on F3, combat areas on F6, a dev readout on F1 — and once there
## are three keys to remember there is no way to simply LOOK at the game. That matters more than it
## sounds: judging whether a fight READS right is impossible through a screen full of rings and
## numbers, and the moment you want a clean look is always mid-fight, never before it.
##
## It OVERRIDES the other flags rather than clearing them, so switching it back off restores exactly
## the debug view you had instead of making you set it up again.
var clean := false


## Should this debug drawing show? Everything that draws for the developer rather than for the
## player asks through here instead of reading its own flag directly, so one switch covers all of
## it and a view added later cannot forget to obey.
func visible_debug(flag: bool) -> bool:
	return flag and not clean


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match (event as InputEventKey).physical_keycode:
		KEY_F3:
			if event.shift_pressed:
				clean = not clean
				print("[Dbg] %s" % ("CLEAN VIEW — everything hidden" if clean else "debug views back"))
				get_viewport().set_input_as_handled()
			else:
				show_hitboxes = not show_hitboxes
				print("[Dbg] hitbox view: ", "ON" if show_hitboxes else "OFF")
