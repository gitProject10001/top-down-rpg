#!/usr/bin/env python3
"""Download DI SVILUPPO, esplicito, del pacchetto NPC offline (runtime llama.cpp + pesi GGUF + licenze).

Legge assets/npc_ai/npc_package_manifest.json e scarica SOLO quello che viene chiesto dalla riga di comando.
Nessun download parte dal gioco: questo strumento e' l'unico punto in cui il progetto tocca la rete.
Ogni file viene verificato per dimensione e sha256 dichiarati nel manifest prima di essere accettato.

Esempi (dalla radice del worktree NPC):
	python tools/npc_ai/fetch_npc_package.py --list
	python tools/npc_ai/fetch_npc_package.py --runtime
	python tools/npc_ai/fetch_npc_package.py --model qwen3.5-2b --model smollm3-3b
	python tools/npc_ai/fetch_npc_package.py --licenses
	python tools/npc_ai/fetch_npc_package.py --verify-only

Codici di uscita: 0 ok, 1 errore d'uso o di rete, 2 verifica fallita (dimensione/sha256), 3 rifiuto (runtime vivo).
Solo libreria standard: nessuna dipendenza da installare.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
PACKAGE_DIR = ROOT / "assets" / "npc_ai"
MANIFEST_PATH = PACKAGE_DIR / "npc_package_manifest.json"
USER_AGENT = "top-down-rpg-npc-ai-fetch/1 (dev tool; explicit download)"
CHUNK = 1 << 20
FLAGS_OF_INTEREST = [
	"--api-key", "--api-key-file", "LLAMA_API_KEY", "--reasoning-budget", "--reasoning-format",
	"--chat-template-kwargs", "--no-webui", "--no-slots", "--log-file", "--jinja", "-ngl",
	"--load-mode", "--prio", "--sleep-idle-seconds", "--sse-ping-interval", "--host", "--port",
]
VC_RUNTIME_DLLS = ["vcruntime140.dll", "vcruntime140_1.dll", "msvcp140.dll", "vcomp140.dll"]


def log(message: str) -> None:
	print(f"[fetch_npc_package] {message}", flush=True)


def load_manifest() -> dict:
	with MANIFEST_PATH.open("r", encoding="utf-8") as handle:
		return json.load(handle)


def sha256_of(path: Path) -> str:
	digest = hashlib.sha256()
	with path.open("rb") as handle:
		while True:
			block = handle.read(CHUNK)
			if not block:
				break
			digest.update(block)
	return digest.hexdigest()


def verify_file(path: Path, size: int, sha256: str, label: str) -> bool:
	if not path.exists():
		log(f"MANCANTE {label}: {path}")
		return False
	actual_size = path.stat().st_size
	if size and actual_size != size:
		log(f"DIMENSIONE ERRATA {label}: attesi {size} byte, trovati {actual_size}")
		return False
	log(f"calcolo sha256 di {path.name} ({actual_size} byte)...")
	actual = sha256_of(path)
	if sha256 and actual != sha256:
		log(f"SHA256 ERRATO {label}: atteso {sha256}, trovato {actual}")
		return False
	log(f"OK {label}: {path.name} sha256={actual}")
	return True


def download(url: str, dest: Path, size: int, sha256: str, label: str, force: bool) -> bool:
	if dest.exists() and not force:
		if verify_file(dest, size, sha256, label):
			log(f"gia' presente e verificato: {dest.name}")
			return True
		log(f"file presente ma non valido, lo riscarico: {dest.name}")
	dest.parent.mkdir(parents=True, exist_ok=True)
	part = dest.with_suffix(dest.suffix + ".part")
	log(f"scarico {label}\n  origine: {url}\n  destinazione: {dest}\n  attesi: {size} byte, sha256 {sha256[:16]}...")
	request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
	started = time.time()
	received = 0
	next_report = 0.05
	try:
		with urllib.request.urlopen(request, timeout=60) as response, part.open("wb") as handle:
			total = int(response.headers.get("Content-Length") or size or 0)
			while True:
				block = response.read(CHUNK)
				if not block:
					break
				handle.write(block)
				received += len(block)
				if total and received / total >= next_report:
					elapsed = max(time.time() - started, 1e-3)
					log(f"  {received * 100 // total:3d}%  {received / (1 << 20):8.1f} MiB  {received / (1 << 20) / elapsed:6.1f} MiB/s")
					next_report += 0.05
	except (urllib.error.URLError, OSError) as error:
		log(f"ERRORE di rete su {label}: {error}")
		return False
	elapsed = time.time() - started
	log(f"ricevuti {received} byte in {elapsed:.1f} s")
	if not verify_file(part, size, sha256, label):
		part.unlink(missing_ok=True)
		return False
	if dest.exists():
		dest.unlink()
	part.rename(dest)
	strip_zone_identifier(dest)
	return True


def strip_zone_identifier(path: Path) -> None:
	"""Rimuove il Mark-of-the-Web (flusso Zone.Identifier) che Windows applica ai file scaricati."""
	if os.name != "nt":
		return
	try:
		os.remove(f"{path}:Zone.Identifier")
	except OSError:
		pass


def godot_user_dir() -> Path | None:
	appdata = os.environ.get("APPDATA")
	if not appdata:
		return None
	return Path(appdata) / "Godot" / "app_userdata" / "Top-Down RPG"


def pid_is_alive(pid: int) -> bool:
	if os.name != "nt":
		try:
			os.kill(pid, 0)
			return True
		except OSError:
			return False
	try:
		output = subprocess.run(
			["tasklist", "/FI", f"PID eq {pid}", "/NH", "/FO", "CSV"],
			capture_output=True, text=True, timeout=15, check=False,
		).stdout
	except (OSError, subprocess.SubprocessError):
		return False
	return f'"{pid}"' in output


def live_runtime_state_files() -> list[Path]:
	"""File di stato scritti dal backend Godot il cui llama-server risulta ancora vivo."""
	user_dir = godot_user_dir()
	if user_dir is None:
		return []
	state_dir = user_dir / "npc_ai" / "state"
	if not state_dir.is_dir():
		return []
	alive: list[Path] = []
	for state_file in state_dir.glob("llama_server_*.json"):
		try:
			data = json.loads(state_file.read_text(encoding="utf-8"))
		except (OSError, ValueError):
			continue
		pid = int(data.get("pid", 0) or 0)
		if pid > 0 and pid_is_alive(pid):
			alive.append(state_file)
	return alive


def refuse_if_runtime_alive(force: bool, targets: list[Path]) -> None:
	"""Rifiuta solo se uno dei file da scrivere e' in uso da un llama-server vivo (scaricare ALTRI file e' sicuro)."""
	if force:
		return
	for state_file in live_runtime_state_files():
		try:
			data = json.loads(state_file.read_text(encoding="utf-8"))
		except (OSError, ValueError):
			continue
		in_use = {Path(str(data.get("model_path", ""))).resolve(), Path(str(data.get("executable", ""))).resolve().parent}
		for target in targets:
			resolved = target.resolve()
			if resolved in in_use or resolved.parent in in_use and target.suffix.lower() != ".gguf":
				log(f"{target} e' in uso da un llama-server vivo (stato: {state_file}): fermalo dal gioco o usa --force")
				sys.exit(3)


def fetch_runtime(manifest: dict, variant_name: str, force: bool) -> bool:
	runtime = manifest["runtime"]
	variant = runtime["variants"][variant_name]
	runtime_dir = PACKAGE_DIR / runtime["install_dir"]
	download_dir = runtime_dir / "_download"
	zip_path = download_dir / variant["file"]
	if not download(variant["url"], zip_path, variant["size"], variant["sha256"], f"runtime {variant_name} {runtime['tag']}", force):
		return False
	log(f"estraggo {zip_path.name} in {runtime_dir}")
	with zipfile.ZipFile(zip_path) as archive:
		names = archive.namelist()
		prefix = common_zip_prefix(names)
		for member in archive.infolist():
			if member.is_dir():
				continue
			relative = member.filename[len(prefix):] if prefix and member.filename.startswith(prefix) else member.filename
			if not relative or relative.startswith("_download/"):
				continue
			target = runtime_dir / relative
			target.parent.mkdir(parents=True, exist_ok=True)
			with archive.open(member) as source, target.open("wb") as sink:
				shutil.copyfileobj(source, sink)
			strip_zone_identifier(target)
	extracted = sorted(p.relative_to(runtime_dir).as_posix() for p in runtime_dir.rglob("*") if p.is_file() and "_download" not in p.parts)
	listing = runtime_dir / "CONTENTS.txt"
	listing.write_text(
		f"# Contenuto estratto da {variant['file']} (tag {runtime['tag']}, sha256 {variant['sha256']})\n" + "\n".join(extracted) + "\n",
		encoding="utf-8",
	)
	log(f"{len(extracted)} file estratti; elenco in {listing}")
	missing = [name for name in runtime["expected_files"] if not (runtime_dir / name).exists()]
	if missing:
		log(f"ATTENZIONE: file attesi dal manifest non trovati nello zip: {missing}")
	present_vc = [name for name in VC_RUNTIME_DLLS if (runtime_dir / name).exists()]
	if present_vc:
		log(f"runtime VC++ incluso nello zip: {present_vc}")
	else:
		log("runtime VC++ (vcruntime140/msvcp140/vcomp140) NON incluso nello zip: su una macchina pulita potrebbe servire il Microsoft Visual C++ Redistributable. Da riportare nel documento.")
	record_server_help(runtime_dir / runtime["executable"], runtime_dir / "llama-server-help.txt")
	return not missing


def common_zip_prefix(names: list[str]) -> str:
	"""Se tutti i membri stanno in una sola cartella radice, restituisce quel prefisso da appiattire."""
	roots = {name.split("/", 1)[0] for name in names if name and not name.endswith("/") or "/" in name}
	if len(roots) == 1:
		root = roots.pop()
		if all(name.startswith(root + "/") for name in names if name and not name.endswith("/")):
			return root + "/"
	return ""


def record_server_help(executable: Path, output_path: Path) -> None:
	if not executable.exists():
		log(f"eseguibile assente, salto --help: {executable}")
		return
	log(f"eseguo {executable.name} --help per registrare i flag disponibili nella build")
	try:
		result = subprocess.run([str(executable), "--help"], capture_output=True, text=True, timeout=60, check=False,
			creationflags=getattr(subprocess, "CREATE_NO_WINDOW", 0))
	except (OSError, subprocess.SubprocessError) as error:
		log(f"impossibile eseguire --help: {error}")
		return
	text = (result.stdout or "") + (result.stderr or "")
	output_path.write_text(text, encoding="utf-8")
	log(f"--help salvato in {output_path} ({len(text)} caratteri, exit {result.returncode})")
	for flag in FLAGS_OF_INTEREST:
		log(f"  {'presente' if flag in text else 'ASSENTE '}  {flag}")


def fetch_model(manifest: dict, model_id: str, force: bool) -> bool:
	entry = next((m for m in manifest["models"] if m["id"] == model_id), None)
	if entry is None:
		log(f"modello sconosciuto nel manifest: {model_id}")
		return False
	dest = PACKAGE_DIR / manifest["models_dir"] / entry["file"]
	ok = download(entry["url"], dest, entry["size"], entry["sha256"], f"modello {model_id}", force)
	if ok:
		fetch_license(entry["license_urls"], PACKAGE_DIR / manifest["licenses_dir"] / entry["license_file"], f"licenza {model_id}")
	return ok


def fetch_license(urls: list[str], dest: Path, label: str) -> bool:
	dest.parent.mkdir(parents=True, exist_ok=True)
	for url in urls:
		request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
		try:
			with urllib.request.urlopen(request, timeout=30) as response:
				body = response.read()
		except (urllib.error.URLError, OSError) as error:
			log(f"{label}: {url} non disponibile ({error}); provo l'origine successiva")
			continue
		if len(body) < 200 or b"<html" in body[:400].lower():
			log(f"{label}: {url} non sembra un testo di licenza; provo l'origine successiva")
			continue
		header = f"# Origine: {url}\n# Scaricato da tools/npc_ai/fetch_npc_package.py\n\n".encode("utf-8")
		dest.write_bytes(header + body)
		log(f"{label}: salvata in {dest} ({len(body)} byte) da {url}")
		return True
	log(f"{label}: NESSUNA origine disponibile ({urls})")
	return False


def fetch_licenses(manifest: dict) -> bool:
	ok = True
	for entry in manifest["licenses"]:
		ok = fetch_license(entry["urls"], PACKAGE_DIR / manifest["licenses_dir"] / entry["file"], entry["name"]) and ok
	return ok


def verify_all(manifest: dict) -> bool:
	ok = True
	runtime = manifest["runtime"]
	runtime_dir = PACKAGE_DIR / runtime["install_dir"]
	for name in runtime["expected_files"]:
		path = runtime_dir / name
		if path.exists():
			log(f"OK runtime: {name} ({path.stat().st_size} byte)")
		else:
			log(f"MANCANTE runtime: {name}")
			ok = False
	for variant_name, variant in runtime["variants"].items():
		zip_path = runtime_dir / "_download" / variant["file"]
		if zip_path.exists():
			ok = verify_file(zip_path, variant["size"], variant["sha256"], f"zip runtime {variant_name}") and ok
	for entry in manifest["models"]:
		path = PACKAGE_DIR / manifest["models_dir"] / entry["file"]
		if path.exists():
			ok = verify_file(path, entry["size"], entry["sha256"], f"modello {entry['id']}") and ok
		else:
			log(f"assente (non scaricato): modello {entry['id']} -> {path.name}")
	return ok


def list_manifest(manifest: dict) -> None:
	runtime = manifest["runtime"]
	print(f"Runtime: {runtime['name']} tag {runtime['tag']} ({runtime['license']})")
	for variant_name, variant in runtime["variants"].items():
		print(f"  variante {variant_name}: {variant['file']} {variant['size']} byte sha256 {variant['sha256']}")
	print(f"Modello predefinito: {manifest['default_model']}")
	for entry in manifest["models"]:
		path = PACKAGE_DIR / manifest["models_dir"] / entry["file"]
		state = "presente" if path.exists() else "assente"
		print(f"  {entry['id']:24s} {entry['params']:4s} {entry['quantization']:7s} {entry['size']:>11d} byte  {entry['license']:10s} [{entry['role']}] {state}")
		print(f"      {entry['url']}")


def main(argv: list[str]) -> int:
	parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
	parser.add_argument("--list", action="store_true", help="mostra il manifest e lo stato locale")
	parser.add_argument("--runtime", nargs="?", const="__default__", metavar="VARIANTE", help="scarica ed estrae il runtime (default: variante del manifest)")
	parser.add_argument("--model", action="append", default=[], metavar="ID", help="scarica un modello del manifest (ripetibile)")
	parser.add_argument("--all-models", action="store_true", help="scarica tutti i modelli candidati (non gli opzionali)")
	parser.add_argument("--licenses", action="store_true", help="scarica i testi delle licenze del runtime")
	parser.add_argument("--verify-only", action="store_true", help="verifica dimensioni e sha256 dei file presenti, senza rete")
	parser.add_argument("--force", action="store_true", help="riscarica anche se presente; ignora il controllo del server vivo")
	args = parser.parse_args(argv)

	manifest = load_manifest()
	if args.list:
		list_manifest(manifest)
		return 0
	if args.verify_only:
		return 0 if verify_all(manifest) else 2
	wanted_models = list(args.model)
	if args.all_models:
		wanted_models += [m["id"] for m in manifest["models"] if m["role"] == "candidate" and m["id"] not in wanted_models]
	if not (args.runtime or wanted_models or args.licenses):
		parser.print_help()
		return 1
	targets: list[Path] = []
	if args.runtime:
		targets.append(PACKAGE_DIR / manifest["runtime"]["install_dir"] / manifest["runtime"]["executable"])
	for model_id in wanted_models:
		entry = next((m for m in manifest["models"] if m["id"] == model_id), None)
		if entry is not None:
			targets.append(PACKAGE_DIR / manifest["models_dir"] / entry["file"])
	if targets:
		refuse_if_runtime_alive(args.force, targets)
	ok = True
	if args.runtime:
		variant = manifest["runtime"]["default_variant"] if args.runtime == "__default__" else args.runtime
		ok = fetch_runtime(manifest, variant, args.force) and ok
		ok = fetch_licenses(manifest) and ok
	if args.licenses and not args.runtime:
		ok = fetch_licenses(manifest) and ok
	for model_id in wanted_models:
		ok = fetch_model(manifest, model_id, args.force) and ok
	log("completato" if ok else "completato CON ERRORI")
	return 0 if ok else 2


if __name__ == "__main__":
	sys.exit(main(sys.argv[1:]))
