"""Regenerate the Kanban and mirror world steps in the main implementation table."""
from pathlib import Path
from itertools import zip_longest
ROOT = Path(__file__).resolve().parents[1]
DOCS = ROOT / "docs"
def rows(text, heading):
    section = text.split(heading, 1)[1].split("\n## ", 1)[0].split("\n### ", 1)[0]
    return [tuple(cell.strip() for cell in line.strip().strip("|").split("|"))
            for line in section.splitlines() if line.startswith("| ") and not line.startswith("| ID")]
world = (DOCS / "WORLD_GENERATION_ROADMAP.md").read_text(encoding="utf-8")
world_rows = rows(world, "## Incrementi e criteri di uscita")
arch_path = DOCS / "ARCHITECTURE_GENERATOR_ROADMAP.md"
arch = arch_path.read_text(encoding="utf-8")
start_marker = "<!-- WORLD_PIPELINE_START -->"
end_marker = "<!-- WORLD_PIPELINE_END -->"
if start_marker in arch:
    before, rest = arch.split(start_marker, 1)
    arch = before + rest.split(end_marker, 1)[1]
# Keep the mirrored rows inside the main table, before its first detailed subsection.
heading = "## Sequenza di implementazione"
a, section = arch.split(heading, 1)
table_end = section.index("\n### ")
section = section[:table_end].rstrip() + "\n" + start_marker + "\n" + "\n".join(
    f"| {id_} | {state} | {title} | Pipeline mondo | {criterion} |"
    for id_, state, title, criterion in world_rows
) + "\n" + end_marker + "\n\n" + section[table_end:]
# Markers inside a Markdown table break rendering: place them around an adjacent table.
section = section.replace(start_marker + "\n", start_marker + "\n\n| ID | Stato | Incremento ambientale / integrazione | Dipendenze | Esempio / criterio di uscita |\n|---|---|---|---|---|\n")
arch = a + heading + section
arch_path.write_text(arch, encoding="utf-8")
arch_rows = rows(a + heading + section.split(start_marker,1)[0], heading)
columns = {"TODO": [], "DOING": [], "DONE": []}
for source, items in [("ARCHITECTURE_GENERATOR_ROADMAP.md", arch_rows), ("WORLD_GENERATION_ROADMAP.md", world_rows)]:
    for row in items:
        id_, state, title = row[:3]
        status = "DONE" if state == "FATTO" else "TODO" if state in ("TODO", "RIMANDATO") else "DOING"
        columns[status].append(f"**[{id_}]({source})** — {title}<br>{state}")
output = """# Kanban dei generatori

Board locale versionata, generata dalle tabelle delle roadmap. DOING include le macrofasi parziali; non significa che ci siano più agenti al lavoro. DONE riguarda il criterio della singola card, non l'intero sistema.

**Priorità: A07 — geometrie architettoniche, prima di B01.1. A07: audit eseguito; resta confronto esplicito R10/R13 prima di B01.** Generazione globale da seed e V01 rimandati; R03.3 in backlog. Le card RIMANDATO restano in TODO con stato esplicito.

Le card mantengono gli stati delle roadmap. Il criterio di uscita e le dipendenze sono nelle tabelle collegate; prima di iniziare una card TODO, verificare quelle dipendenze.

Aggiornare stati e criteri nelle tabelle, poi eseguire `python tools/update_generator_board.py`. I link delle card aprono la roadmap di riferimento. Non modificare questa board generata a mano.

| TODO | DOING | DONE |
|---|---|---|
"""
for cells in zip_longest(*columns.values(), fillvalue=""):
    output += "| " + " | ".join(cells) + " |\n"
(DOCS / "GENERATOR_KANBAN.md").write_text(output, encoding="utf-8")
print("Updated implementation sequence and GENERATOR_KANBAN.md")
