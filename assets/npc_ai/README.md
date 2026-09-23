# Pacchetto NPC offline

Tutto quello che serve al fabbro conversazionale per funzionare senza rete, account, chiavi o
installazioni manuali: runtime di inferenza, pesi del modello, licenze e manifest. In questa cartella
stanno **solo** i file piccoli e testuali; binari e pesi vengono scaricati dallo sviluppatore con uno
strumento esplicito e restano fuori da Git (`runtime/.gitignore`, `models/.gitignore`) e fuori dalla
scansione di Godot (`.gdignore`). Il gioco non scarica mai nulla.

| Cartella / file | Contenuto | In Git | Nel PCK esportato |
| --- | --- | --- | --- |
| `npc_package_manifest.json` | versione, origine, dimensione, sha256 e licenza di runtime e modelli; flag del server | sì | sì |
| `blacksmith_profile.tres` | identita', tono, fatti pubblici, conoscenze autorizzate, battute di ripiego del fabbro | sì | sì |
| `blacksmith_facts.json` | fatti consentiti dal gioco, eventi confermabili, segreti-fixture, stato di gioco-fixture | sì | sì |
| `world_lore.json` | lore condivisa fra tutti gli NPC (PROVVISORIA): una frase per voce, etichette, `known_by`, priorita', `always`, `secret` | sì | sì |
| `licenses/` | testi delle licenze di llama.cpp (MIT), BoringSSL, LLVM OpenMP, Apache-2.0 dei modelli | sì | no: copiati accanto all'exe dal tool di packaging |
| `runtime/` | zip llama.cpp `b10964` estratto (Windows x64 Vulkan); nel pacchetto finiscono solo `llama-server.exe`, le DLL del manifest, `ggml-cpu-*.dll` e `ggml-vulkan.dll` | **no** | **no**: accanto all'exe in `npc_ai/runtime/` |
| `models/` | pesi GGUF (Q4_K_M) | **no** | **no**: accanto all'exe in `npc_ai/models/` |

## Procedura riproducibile

```powershell
# 1. download di sviluppo, con verifica di dimensione e sha256 (unico punto che tocca la rete)
python tools/npc_ai/fetch_npc_package.py --runtime
python tools/npc_ai/fetch_npc_package.py --model qwen3-4b-instruct-2507
python tools/npc_ai/fetch_npc_package.py --verify-only

# 2. esportare il progetto con i template Godot 4.6.3 (fuori dal perimetro di questo worktree)
# 3. assemblare il pacchetto accanto all'eseguibile esportato
python tools/npc_ai/package_npc_lab.py --exe-dir "C:/percorso/dell/export"
```

In editor il modulo cerca runtime e modello in `res://assets/npc_ai/{runtime,models}`; in un progetto
esportato in `<cartella exe>/npc_ai/{runtime,models}` (`addons/npc_ai/npc_ai_paths.gd`).

## Licenze

- **llama.cpp** (`b10964`): MIT, `licenses/LLAMA_CPP_LICENSE.txt`. Le build Windows linkano **BoringSSL**
  (`licenses/BORINGSSL_LICENSE.txt`) e includono `libomp.dll` con `LICENSE-LLVM-OpenMP`
  (`licenses/LLVM_OPENMP_LICENSE.txt`). La build Vulkan usa il driver di sistema: nessun runtime GPU proprietario.
- **Qwen3-4B-Instruct-2507** (Alibaba/Qwen), modello predefinito: Apache-2.0, `licenses/QWEN3-4B-INSTRUCT-2507_LICENSE.txt`.
- **Qwen3.5-2B** (Alibaba/Qwen), alternativa leggera: Apache-2.0, `licenses/QWEN3.5-2B_LICENSE.txt`.
- **SmolLM3-3B** (HuggingFaceTB), alternativa: Apache-2.0, `licenses/SMOLLM3-3B_LICENSE.txt` (testo canonico: il repo non pubblica un file LICENSE).
- Lo zip di llama.cpp **non** include il runtime Visual C++ (`vcruntime140.dll`, `msvcp140.dll`, `vcomp140.dll`):
  su una macchina pulita potrebbe servire il Microsoft Visual C++ Redistributable, da verificare ed eventualmente includere.

## Cosa NON c'e'

Nessuna chiave API, nessun account, nessuna telemetria, nessun download automatico. Il modello propone
solo testo: non esiste alcun campo o comando con cui possa toccare oggetti, denaro, quest o reputazione.
