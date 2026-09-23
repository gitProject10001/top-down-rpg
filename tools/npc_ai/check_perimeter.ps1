# Verifica che il lavoro NPC resti nel perimetro autorizzato da docs/LOCAL_NPC_AI_TODO.md.
# - i file cambiati rispetto al commit di base stanno solo nei percorsi consentiti;
# - nessun binario, zip o peso GGUF e' tracciato da Git sotto assets/npc_ai;
# - nel modulo addons/npc_ai ogni URL http(s) punta solo a 127.0.0.1 (nessuna chiamata esterna);
# - git diff --check non segnala errori di spazi.
# Uso (dal worktree NPC): powershell -ExecutionPolicy Bypass -File tools/npc_ai/check_perimeter.ps1 [-Base 83977ad]
param(
	[string]$Base = "83977ad",
	[switch]$Staged,
	[switch]$Integration
)
$ErrorActionPreference = "Continue"
$failures = 0
$allowed = @(
	"addons/npc_ai/",
	"assets/npc_ai/",
	"scenes/dev/npc_ai_lab.tscn",
	"scripts/npc_ai_lab/",
	"tools/npc_ai/",
	"docs/NPC_AI_",
	"docs/LOCAL_NPC_AI_TODO.md"
)

$integrationFiles = @("scripts/village/integrated_landscape.gd", "scenes/dev/integrated_landscape.tscn")
if ($Integration) { $allowed += "scenes/npc_ai/" }

function Report([bool]$ok, [string]$label) {
	if ($ok) { Write-Output "OK    $label" } else { Write-Output "ERROR $label"; $script:failures += 1 }
}

$root = git rev-parse --show-toplevel
Set-Location $root

# 1. file cambiati (commit + indice + working tree, esclusi gli ignorati)
if ($Staged) {
	$changed = @(git diff --cached --name-only)
	Write-Output "Audit del solo indice; modifiche non staged escluse esplicitamente."
} else {
	$committed = @(git diff --name-only $Base HEAD)
	$pending = @(git status --porcelain --untracked-files=all | ForEach-Object { $_.Substring(3).Trim('"') })
	$changed = @($committed + $pending | Where-Object { $_ -ne "" } | Sort-Object -Unique)
}
foreach ($file in $changed) {
	$inside = $Integration -and ($integrationFiles -contains $file)
	foreach ($prefix in $allowed) { if ($file.StartsWith($prefix)) { $inside = $true; break } }
	Report $inside "perimetro: $file"
}

# 2. nessun binario o peso tracciato
$tracked = @(git ls-files assets/npc_ai addons/npc_ai tools/npc_ai)
$heavy = @($tracked | Where-Object { $_ -match '\.(gguf|exe|dll|zip|part|bin|safetensors)$' })
Report ($heavy.Count -eq 0) ("nessun binario/peso tracciato (trovati: {0})" -f ($heavy -join ", "))
foreach ($file in $tracked) {
	$size = (Get-Item $file).Length
	Report ($size -lt 2MB) ("file tracciato sotto 2 MB: {0} ({1} byte)" -f $file, $size)
}

# 3. nessuna chiamata esterna nel modulo
$urls = @(Select-String -Path "addons/npc_ai/*.gd", "addons/npc_ai/ui/*.gd", "scripts/npc_ai_lab/*.gd" -Pattern 'https?://' -AllMatches)
foreach ($hit in $urls) {
	foreach ($m in $hit.Matches) {
		$line = $hit.Line
		Report ($line -match '127\.0\.0\.1') ("URL solo loopback in {0}:{1}: {2}" -f $hit.Filename, $hit.LineNumber, $line.Trim())
	}
}
$net = @(Select-String -Path "addons/npc_ai/*.gd", "addons/npc_ai/ui/*.gd" -Pattern 'HTTPRequest|connect_to_host\("(?!127\.0\.0\.1)' )
Report ($net.Count -eq 0) "nessun HTTPRequest o connessione verso host diversi da 127.0.0.1"

# 4. spazi e fine riga
if ($Staged) { git diff --cached --check | Out-Null } else { git diff --check $Base HEAD | Out-Null }
Report ($LASTEXITCODE -eq 0) "git diff --check $Base HEAD"

# 5. file vietati intatti
$forbidden = @("project.godot", "README.md", "scripts/dialogue.gd", "scripts/player.gd", "scripts/combat", "scripts/village", "shaders", "addons/house_builder", "addons/village_builder", "scenes/dev/hearth_village_playable.tscn")
$touched = if ($Staged) { @(git diff --cached --name-only -- $forbidden) } else { @(git diff --name-only $Base HEAD -- $forbidden) }
if ($Integration) { $touched = @($touched | Where-Object { $integrationFiles -notcontains $_ }) }
Report ($touched.Count -eq 0) ("file vietati intatti (toccati: {0})" -f ($touched -join ", "))

Write-Output ("NPC_AI_PERIMETER_CHECK failures={0}" -f $failures)
exit $(if ($failures -eq 0) { 0 } else { 1 })
