#!/usr/bin/env python3
"""Assembla il pacchetto NPC offline accanto a un eseguibile esportato (o in una cartella a scelta).

Copia runtime llama.cpp (senza gli archivi scaricati), il modello scelto, le licenze, il manifest e un
README in <destinazione>/npc_ai/, verificando dimensioni e sha256 dichiarati nel manifest. Non scarica nulla:
se un file manca, dice quale e come ottenerlo con tools/npc_ai/fetch_npc_package.py.

Esempi (dalla radice del worktree NPC):
	python tools/npc_ai/package_npc_lab.py --out dist/npc_ai_package
	python tools/npc_ai/package_npc_lab.py --exe-dir "C:/export/TopDownRpg" --model qwen3.5-2b

Codici di uscita: 0 ok, 1 errore d'uso, 2 file mancanti o checksum errato.
Solo libreria standard.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import shutil
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE_DIR = ROOT / "assets" / "npc_ai"
MANIFEST_PATH = PACKAGE_DIR / "npc_package_manifest.json"
EXCLUDED_RUNTIME = {"_download", ".gdignore", ".gitignore"}
CHUNK = 1 << 20


def log(message: str) -> None:
	print(f"[package_npc_lab] {message}", flush=True)


def sha256_of(path: Path) -> str:
	digest = hashlib.sha256()
	with path.open("rb") as handle:
		while True:
			block = handle.read(CHUNK)
			if not block:
				break
			digest.update(block)
	return digest.hexdigest()


def main(argv: list[str]) -> int:
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--out", help="cartella di destinazione (vi viene creata npc_ai/)")
	parser.add_argument("--exe-dir", help="cartella dell'eseguibile esportato: npc_ai/ viene messa accanto all'exe")
	parser.add_argument("--model", help="id del modello da includere (default: default_model del manifest)")
	parser.add_argument("--skip-hash", action="store_true", help="salta il calcolo sha256 del modello (solo dimensione)")
	args = parser.parse_args(argv)
	if not args.out and not args.exe_dir:
		parser.print_help()
		return 1
	manifest = json.loads(MANIFEST_PATH.read_text(encoding="utf-8"))
	runtime = manifest["runtime"]
	model_id = args.model or manifest["default_model"]
	model = next((m for m in manifest["models"] if m["id"] == model_id), None)
	if model is None:
		log(f"modello sconosciuto: {model_id}")
		return 1
	dest_root = Path(args.exe_dir or args.out).resolve()
	if args.exe_dir:
		exes = list(dest_root.glob("*.exe"))
		if not exes:
			log(f"ATTENZIONE: nessun .exe in {dest_root}: esporta prima il progetto con i template Godot 4.6.3, poi rilancia")
	dest = dest_root / "npc_ai"
	problems = 0

	runtime_src = PACKAGE_DIR / runtime["install_dir"]
	for name in runtime["expected_files"] + [runtime.get("gpu_backend_file", "")]:
		if name and not (runtime_src / name).exists():
			log(f"MANCANTE runtime: {name} (python tools/npc_ai/fetch_npc_package.py --runtime)")
			problems += 1
	license_file = PACKAGE_DIR / manifest["licenses_dir"] / model.get("license_file", "")
	if not model.get("license_file") or not license_file.exists():
		log(f"MANCANTE licenza del modello {model_id}: {license_file} (python tools/npc_ai/fetch_npc_package.py --model {model_id} la scarica)")
		problems += 1
	model_src = PACKAGE_DIR / manifest["models_dir"] / model["file"]
	if not model_src.exists():
		log(f"MANCANTE modello: {model_src} (python tools/npc_ai/fetch_npc_package.py --model {model_id})")
		problems += 1
	elif model_src.stat().st_size != model["size"]:
		log(f"DIMENSIONE ERRATA modello: {model_src.stat().st_size} != {model['size']}")
		problems += 1
	elif not args.skip_hash:
		log(f"calcolo sha256 di {model['file']}...")
		actual = sha256_of(model_src)
		if actual != model["sha256"]:
			log(f"SHA256 ERRATO modello: {actual} != {model['sha256']}")
			problems += 1
	if problems:
		log("pacchetto NON assemblato: risolvi i punti sopra")
		return 2

	if dest.exists():
		shutil.rmtree(dest)
	(dest / runtime["install_dir"]).mkdir(parents=True)
	copied = []
	# Lista esplicita: solo il server, le DLL che usa e le varianti CPU. Niente llama-cli, quantize, rpc-server...
	wanted = set(runtime["expected_files"]) | {runtime.get("gpu_backend_file", "")} | set(runtime.get("bundled_license_files", []))
	for item in sorted(runtime_src.iterdir()):
		if item.is_dir() or item.name in EXCLUDED_RUNTIME:
			continue
		if item.name not in wanted and not (item.name.startswith("ggml-cpu-") and item.suffix.lower() == ".dll"):
			continue
		shutil.copy2(item, dest / runtime["install_dir"] / item.name)
		copied.append(f"{runtime['install_dir']}/{item.name}")
	for name in sorted(wanted):
		if name and not (dest / runtime["install_dir"] / name).exists():
			log(f"ATTENZIONE: file atteso non copiato: {name}")
	(dest / manifest["models_dir"]).mkdir()
	shutil.copy2(model_src, dest / manifest["models_dir"] / model["file"])
	copied.append(f"{manifest['models_dir']}/{model['file']}")
	licenses_src = PACKAGE_DIR / manifest["licenses_dir"]
	(dest / manifest["licenses_dir"]).mkdir()
	for item in sorted(licenses_src.glob("*")):
		if item.is_file():
			shutil.copy2(item, dest / manifest["licenses_dir"] / item.name)
			copied.append(f"{manifest['licenses_dir']}/{item.name}")
	for extra in runtime.get("bundled_license_files", []):
		src = runtime_src / extra
		if src.exists():
			shutil.copy2(src, dest / manifest["licenses_dir"] / extra)
			copied.append(f"{manifest['licenses_dir']}/{extra}")
	shutil.copy2(MANIFEST_PATH, dest / MANIFEST_PATH.name)
	readme = PACKAGE_DIR / "README.md"
	if readme.exists():
		shutil.copy2(readme, dest / "README.md")
	# il pacchetto porta un solo modello: il manifest copiato dichiara quale
	packaged = json.loads((dest / MANIFEST_PATH.name).read_text(encoding="utf-8"))
	packaged["default_model"] = model_id
	packaged["packaged_models"] = [model_id]
	(dest / MANIFEST_PATH.name).write_text(json.dumps(packaged, indent="\t", ensure_ascii=False) + "\n", encoding="utf-8")
	total = sum((dest / rel).stat().st_size for rel in copied)
	info = [
		f"Pacchetto NPC offline assemblato in {dest}",
		f"runtime: llama.cpp {runtime['tag']} ({runtime['license']}), variante {runtime['default_variant']}",
		f"modello: {model['display_name']} ({model['license']}) sha256 {model['sha256']}",
		f"file copiati: {len(copied)}, {total / (1 << 20):.1f} MiB",
		"",
		"Verifiche ancora da eseguire a mano (non dichiarate superate):",
		"  1. esportare il progetto con i template Godot 4.6.3 (nessun preset in questo worktree);",
		"  2. avviare l'exe su una macchina pulita SENZA rete e senza dipendenze installate a mano;",
		"  3. se Windows segnala DLL mancanti (vcruntime140/msvcp140/vcomp140), servono i Microsoft Visual C++",
		"     Redistributable: lo zip llama.cpp non li include (vc_runtime_included=false nel manifest);",
		"  4. controllare che nessun llama-server.exe resti attivo dopo la chiusura del gioco.",
	]
	(dest / "PACKAGE_INFO.txt").write_text("\n".join(info) + "\n", encoding="utf-8")
	for line in info:
		log(line)
	return 0


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
