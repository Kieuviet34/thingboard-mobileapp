<#
  Local equivalent of the CI gates. Run from anywhere:

    powershell -ExecutionPolicy Bypass -File tools/qa/run_checks.ps1
    powershell -ExecutionPolicy Bypass -File tools/qa/run_checks.ps1 -Spec C:\tmp\tb-openapi.json
    powershell -ExecutionPolicy Bypass -File tools/qa/run_checks.ps1 -SkipTests

  Gates: format check, analyze (--fatal-infos), tests + coverage floors, and, when -Spec is
  given, the ThingsBoard contract audits. Exit code is non-zero if any gate fails.
  The Android build is separate (it starts Gradle): use `flutter build apk --debug`, and on
  this machine go through ~/.claude/scripts/jvm-ondemand.ps1 so daemons are stopped after.
#>
param(
  [string]$Flutter = $(if ($env:FLUTTER_BIN) { $env:FLUTTER_BIN } else { 'flutter' }),
  [string]$Dart = $(if ($env:DART_BIN) { $env:DART_BIN } else { 'dart' }),
  [string]$Spec,
  [switch]$SkipTests
)

$ErrorActionPreference = 'Continue'
Set-Location (Resolve-Path (Join-Path $PSScriptRoot '..\..'))
$results = [System.Collections.Generic.List[object]]::new()

function Invoke-Gate([string]$Name, [scriptblock]$Body) {
  Write-Host "`n=== $Name ===" -ForegroundColor Cyan
  $watch = [System.Diagnostics.Stopwatch]::StartNew()
  & $Body
  $code = $LASTEXITCODE
  $watch.Stop()
  $results.Add([pscustomobject]@{
      Gate    = $Name
      Result  = if ($code -eq 0) { 'PASS' } else { 'FAIL' }
      Seconds = [math]::Round($watch.Elapsed.TotalSeconds, 1)
    })
}

Invoke-Gate 'format' { & $Dart format --output=none --set-exit-if-changed . }
Invoke-Gate 'analyze' { & $Flutter analyze --fatal-infos }

if (-not $SkipTests) {
  Invoke-Gate 'tests + coverage' { & $Flutter test --coverage }
  Invoke-Gate 'coverage floors' {
    python -I tools/qa/check_coverage.py --min 80 --floor lib/core/api=80 --floor lib/widgets=80
  }
}

if ($Spec) {
  $allow = 'tools/api_contract/known_deviations.json'
  Invoke-Gate 'contract: endpoints' { python -I tools/api_contract/audit_endpoints.py --spec $Spec --allow $allow }
  Invoke-Gate 'contract: models' { python -I tools/api_contract/audit_models.py --spec $Spec --allow $allow }
  Invoke-Gate 'contract: snapshot current' {
    # Hash before/after (not `git diff`) so it also works while the file is untracked.
    $snapshot = 'test/fixtures/contract/tb_pe_4_4_1_subset.json'
    $before = (Get-FileHash $snapshot).Hash
    python -I tools/api_contract/build_subset.py --spec $Spec
    if ($LASTEXITCODE -eq 0 -and (Get-FileHash $snapshot).Hash -ne $before) {
      Write-Host "Snapshot was out of date and has been regenerated: review and commit $snapshot" -ForegroundColor Yellow
      $global:LASTEXITCODE = 1
    }
  }
} else {
  Write-Host "`n(contract audits skipped: pass -Spec <openapi.json>; see docs/qa/API_CONTRACT.md)" -ForegroundColor DarkGray
}

Write-Host "`n=== Summary ===" -ForegroundColor Cyan
$results | Format-Table -AutoSize
if ($results | Where-Object Result -eq 'FAIL') { exit 1 }
exit 0
