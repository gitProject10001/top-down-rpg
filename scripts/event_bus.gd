extends Node
## Global signal hub — registered as the autoload singleton "EventBus".
##
## WHY this exists:
##   Unrelated systems (HUD, audio, score, save) often need to react to the same
##   moment ("the player died") without holding hard references to each other.
##   Routing those moments through one well-named signal bus keeps systems decoupled.
##
## DISCIPLINE:
##   An EventBus is easy to abuse into an untraceable mess. Keep the signal list
##   SHORT, name signals after the *event* (past tense), and document the payload.
##   If only two nodes ever talk, connect them directly instead of adding a signal here.

signal player_died                      ## Player health reached zero.
signal enemy_died(enemy: Node)          ## An enemy was destroyed. enemy = the node, pre-free.
signal zone_changed(zone_name: String)  ## The world finished streaming to a new zone.
signal combat_impact(strength: float)    ## a hit/parry landed — camera shake & other feedback react.
