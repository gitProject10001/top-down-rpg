# Esegue tutti i controlli del modulo NPC in sequenza, con un timeout per ciascuno, e chiude col
# controllo del perimetro. Exit 3 di un test = SKIPPED (runtime o modello non scaricati), non un errore.
# Uso (dal worktree NPC):
#   powershell -ExecutionPolicy Bypass -File tools/npc_ai/run_checks.ps1            # solo backend finto
#   powershell -ExecutionPolicy Bypass -File tools/npc_ai/run_checks.ps1 -Real      # anche llama-server
#   powershell -ExecutionPolicy Bypass -File tools/npc_ai/run_checks.ps1 -Real -Bench   # anche il bench in finestra
param(
	[string]$Godot = "C:/Users/jonny/Desktop/game/godot/Godot_v4.6.3-stable_win64_console.exe",
	[switch]$Real,
	[switch]$Bench,
	[switch]$StagedIntegration
)
$ErrorActionPreference = "Continue"
$root = git rev-parse --show-toplevel
Set-Location $root

$tests = @(
	@{ name = "check_npc_contract"; args = @(); timeout = 120; headless = $true },
	@{ name = "check_npc_context"; args = @(); timeout = 120; headless = $true },
	@{ name = "check_npc_lore"; args = @(); timeout = 120; headless = $true },
	@{ name = "check_npc_memory"; args = @(); timeout = 120; headless = $true },
	@{ name = "check_npc_service"; args = @(); timeout = 180; headless = $true },
	@{ name = "check_npc_lab_smoke"; args = @(); timeout = 120; headless = $true },
	@{ name = "check_npc_manipulation"; args = @(); timeout = 300; headless = $true }
)
if ($Real) {
	$tests += @{ name = "check_npc_streaming"; args = @(); timeout = 420; headless = $true }
	$tests += @{ name = "check_npc_local_backend"; args = @(); timeout = 600; headless = $true }
	$tests += @{ name = "check_npc_manipulation"; args = @("--", "--real"); timeout = 420; headless = $true }
}
if ($Bench) {
	$tests += @{ name = "bench_npc_local"; args = @("--", "--runs", "12"); timeout = 900; headless = $false }
}

$rows = @()
$failed = 0
foreach ($t in $tests) {
	$argList = @()
	if ($t.headless) { $argList += "--headless" }
	$argList += @("--path", ".", "--script", ("res://tools/npc_ai/{0}.gd" -f $t.name))
	$argList += $t.args
	$logDir = Join-Path $env:APPDATA "Godot/app_userdata/Top-Down RPG/npc_ai/logs/checks"
	New-Item -ItemType Directory -Force -Path $logDir | Out-Null
	$log = Join-Path $logDir ("{0}{1}.log" -f $t.name, $(if ($t.args -contains "--real") { "_real" } else { "" }))
	$sw = [System.Diagnostics.Stopwatch]::StartNew()
	$proc = Start-Process -FilePath $Godot -ArgumentList $argList -NoNewWindow -PassThru -RedirectStandardOutput $log
	$null = $proc.Handle   # PowerShell 5.1: senza toccare l'handle prima dell'uscita, ExitCode resta vuoto
	$finished = $proc.WaitForExit($t.timeout * 1000)
	if (-not $finished) {
		# Termina solo i llama-server avviati da QUESTO processo Godot (file di stato con owner_pid), mai altri.
		$stateDir = Join-Path $env:APPDATA "Godot/app_userdata/Top-Down RPG/npc_ai/state"
		Get-ChildItem -Path $stateDir -Filter ("llama_server_{0}_*.json" -f $proc.Id) -ErrorAction SilentlyContinue | ForEach-Object {
			try {
				$state = Get-Content $_.FullName -Raw | ConvertFrom-Json
				if ($state.owner_pid -eq $proc.Id -and $state.pid -gt 0) { Stop-Process -Id $state.pid -Force -ErrorAction SilentlyContinue }
				Remove-Item $_.FullName -ErrorAction SilentlyContinue
			} catch {}
		}
		Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
		$code = 124
	} else {
		$code = $proc.ExitCode
	}
	$sw.Stop()
	$summary = (Select-String -Path $log -Pattern "_CHECK failures=|_SKIPPED|_RESULT" | Select-Object -Last 1)
	$status = switch ($code) { 0 { "OK" } 3 { "SKIPPED" } 124 { "TIMEOUT" } default { "FAIL" } }
	if ($status -eq "FAIL" -or $status -eq "TIMEOUT") { $failed += 1 }
	$rows += [pscustomobject]@{ test = ($t.name + " " + ($t.args -join " ")).Trim(); status = $status; exit = $code; seconds = [math]::Round($sw.Elapsed.TotalSeconds, 1); summary = $(if ($summary) { $summary.Line.Trim() } else { "" }) }
	Write-Output ("{0,-40} {1,-8} {2,6}s  {3}" -f $rows[-1].test, $status, $rows[-1].seconds, $rows[-1].summary)
}

Write-Output ""
Write-Output "=== perimetro ==="
$perimeterArgs = @()
if ($StagedIntegration) { $perimeterArgs = @("-Staged", "-Integration") }
& powershell -ExecutionPolicy Bypass -File (Join-Path $root "tools/npc_ai/check_perimeter.ps1") @perimeterArgs | Select-Object -Last 3
if ($LASTEXITCODE -ne 0) { $failed += 1 }

Write-Output ""
$rows | Format-Table -AutoSize | Out-String | Write-Output
Write-Output ("NPC_AI_RUN_CHECKS failed={0}" -f $failed)
exit $(if ($failed -eq 0) { 0 } else { 1 })
