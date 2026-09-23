@tool
extends Resource
## Identita' stabile di un NPC conversazionale: chi e', che mestiere fa, come parla, cosa sa e cosa dice
## quando il modello non risponde. E' un dato di gioco fidato: nulla qui viene scritto dal modello o dal
## giocatore. Le conoscenze elencate sono le UNICHE che il contesto puo' consegnare all'inferenza.
const ID_PATTERN := "^[a-z0-9_]{1,32}$"

@export var npc_id := ""                                   ## stabile, ^[a-z0-9_]{1,32}$; nomina memoria e sessioni
@export var display_name := ""
@export var trade := ""                                    ## mestiere, es. "fabbro"
@export var tone := ""                                     ## es. "burbero ma cordiale"
@export_multiline var persona := ""                        ## istruzioni del personaggio, in italiano
@export var rules: PackedStringArray = PackedStringArray() ## regole di stile e di confine
@export var example_lines: PackedStringArray = PackedStringArray() ## battute d'esempio in italiano corretto: ancorano registro e grammatica del modello
@export var public_facts: PackedStringArray = PackedStringArray()       ## cio' che chiunque nel borgo sa
@export var private_knowledge: PackedStringArray = PackedStringArray()  ## conoscenze personali autorizzate dal gioco
@export var greeting_lines: PackedStringArray = PackedStringArray()     ## apertura del dialogo (scritta a mano)
@export var fallback_lines: PackedStringArray = PackedStringArray()     ## ripiego quando il modello manca o sbaglia
@export var interrupted_lines: PackedStringArray = PackedStringArray()  ## quando il giocatore annulla
@export var farewell_lines: PackedStringArray = PackedStringArray()     ## chiusura del dialogo
@export var max_output_chars := 320
@export var max_output_tokens := 120


func is_valid() -> bool:
	return _id_valid() and display_name != "" and persona.strip_edges() != "" and fallback_lines.size() >= 3


func problems() -> PackedStringArray:
	var out := PackedStringArray()
	if not _id_valid():
		out.append("npc_id non valido (atteso " + ID_PATTERN + ")")
	if display_name == "":
		out.append("display_name vuoto")
	if persona.strip_edges() == "":
		out.append("persona vuota")
	if fallback_lines.size() < 3:
		out.append("servono almeno 3 battute di ripiego")
	return out


## Scelta deterministica: lo stesso testo del giocatore porta sempre alla stessa battuta.
func fallback_for(seed_text: String) -> String:
	return _pick(fallback_lines, seed_text, "Mmh. Torna piu' tardi, ho il ferro sul fuoco.")


func interrupted_for(seed_text: String) -> String:
	return _pick(interrupted_lines if not interrupted_lines.is_empty() else fallback_lines, seed_text, "Come vuoi.")


func greeting_for(session_index: int) -> String:
	if greeting_lines.is_empty():
		return "Salve."
	return greeting_lines[absi(session_index) % greeting_lines.size()]


func farewell_for(session_index: int) -> String:
	if farewell_lines.is_empty():
		return "Buon cammino."
	return farewell_lines[absi(session_index) % farewell_lines.size()]


func _pick(lines: PackedStringArray, seed_text: String, default_line: String) -> String:
	if lines.is_empty():
		return default_line
	# hash() di una String e' stabile fra esecuzioni in Godot 4 (djb2 sul contenuto).
	var index := absi(hash(seed_text.strip_edges().to_lower())) % lines.size()
	return lines[index]


func _id_valid() -> bool:
	var re := RegEx.new()
	re.compile(ID_PATTERN)
	return re.search(npc_id) != null
