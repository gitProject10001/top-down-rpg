@tool
extends RefCounted
## THE STREAM IS THE ADDON'S, not ours. Open World Database (asset 4166) spawns and despawns the
## world's units around a focal point; this file is only the three places a generated world has
## to disagree with its defaults, each of which fails SILENTLY if left alone.
##
##   attach()   the manifest lives beside the WORLD, not beside the current scene (world_db.gd).
##   warm()     the player is teleported onto the spawn one physics frame after the zone is
##              added, so the ground under them cannot arrive on a later batch.
##
## What is NOT here is the third thing this file used to do — see the note at the bottom.
##
## Everything else — which chunk a unit belongs to, what is in range, when to free it — is the
## addon's own and is not second-guessed here.

const Db := preload("res://scripts/world/world_db.gd")


## Point an OpenWorldDatabase at a world's own `.owdb`, and load it. Returns how many units the
## manifest holds. The addon already loaded (nothing) from its own path in `_ready`, which runs
## before the zone's — `_load_database_from_path` clears what it holds first, so this replaces
## that rather than adding to it.
static func attach(owdb: Node, db_path: String) -> int:
	if owdb == null:
		return 0
	if not FileAccess.file_exists(db_path):
		push_warning("[World] no manifest at %s — nothing will stream" % db_path)
		return 0
	owdb.database = Db.new(owdb, db_path)
	owdb.is_loading = true
	owdb.database.load_database()
	owdb.is_loading = false
	return int(owdb.get_total_database_nodes())


## THE GROUND ON FRAME ZERO. `World.go_to` waits exactly one physics frame between adding a zone
## and putting the player on its spawn, so whatever holds them up has to be standing by then.
## With batching off the addon's `load_node` runs `_immediate_load_node` inline, and
## `force_process_queues` drains anything already queued — so this is the addon's own
## synchronous path, not a spin loop and not `load_all_chunks` (which would load the whole world
## and defeat the point). Returns how many units are up.
static func warm(owdb: Node, focus: Node) -> int:
	if owdb == null or focus == null:
		return 0
	var was := bool(owdb.batch_processing_enabled)
	owdb.batch_processing_enabled = false
	owdb.update_batch_settings()
	focus.call("force_update")
	if owdb.batch_processor != null:
		owdb.batch_processor.force_process_queues()
	owdb.batch_processing_enabled = was
	owdb.update_batch_settings()
	return int(owdb.get_currently_loaded_nodes())


## THERE IS NO `disown` HERE ANY MORE, and its absence is the point. The addon gives every node
## it loads an owner (`batch_processor.gd:210`), and an owned node is a row in the Scene dock —
## that IS how a streamed world becomes visible and selectable in the editor. Stripping it, as
## this file used to, fought the addon's own mechanism for the thing the world most needed.
## The cost is that saving an open world snapshots whatever was streamed at that moment into the
## .tscn; the addon frees those on the next open and rebuilds from the manifest, so it is diff
## churn and not data loss.
