extends State
## Aboard the raft. The deck does the moving — the body is parented under it with its collider
## off, so this state's whole job is to stand quietly and hand `interact` back to the raft.
## No gravity, no move_and_slide: a body glued to a deck that applies either would fight it.


func enter() -> void:
	player.velocity = Vector3.ZERO


func exit() -> void:
	# ANY transition out of Ride that is not the raft's own disembark — Hurt, Dead, whatever
	# combat decides — must not strand a colliderless body under the deck forever. If we are
	# still parented there, the raft lets go right now; after a normal disembark the parent
	# chain no longer reaches it and this is a no-op.
	var raft := _raft()
	if raft != null:
		raft.force_eject()


func handle_input(event: InputEvent) -> void:
	if event.is_action_pressed("interact"):
		var raft := _raft()
		if raft != null:
			raft.disembark()
			# The raft also listens for interact on this same event — one press must not
			# step off AND board again.
			player.get_viewport().set_input_as_handled()


## The deck chain: Player -> Deck -> Raft. Duck-typed on disembark(), no class coupling.
func _raft() -> Node:
	var n: Node = player.get_parent()
	while n != null and not n.has_method("disembark"):
		n = n.get_parent()
	return n
