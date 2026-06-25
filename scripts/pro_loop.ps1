param(
  [ValidateSet("local", "pro", "required-pro", "testline", "status", "audit", "recon", "gain", "debt", "help", "off")]
  [string]$Command = "help",
  [string]$Root = ".",
  [string]$TargetChatGptUrl,
  [switch]$ConfirmTestlineIsolation,
  [int]$TargetScore = 95,
  [string]$AuditContext = "",
  [string]$ModuleGoal,
  [string]$ModuleCategory,
  [switch]$AllowWebResearch,
  [switch]$AllowToolDiscovery,
  [string]$DebtNote,
  [string]$DebtTrigger
)

$ErrorActionPreference = "Stop"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$MainScript = Join-Path $ScriptDir "gpt_pro_review_loop.ps1"

function Resolve-LoopRoot {
  param([string]$Path)
  return (Resolve-Path -LiteralPath $Path).Path
}

function Show-Help {
  @"
Pro Loop thin command surface

Commands:
  local        Init default local loop and run one local-first iteration.
  pro          Enable optional GPT Pro review for the supplied ChatGPT URL and prepare a handoff.
  required-pro Enable required GPT Pro mode for project-total completion gates.
  testline     Enter isolated 95-point candidate loop. Requires -ConfirmTestlineIsolation.
  status       Show current loop state.
  audit        Run capability scan and periodic efficiency audit.
  recon        Write a compact reuse reconnaissance decision package.
  gain         Show compact local gain metrics from the loop ledger.
  debt         List or record pro-loop debt notes.
  off          Force fully local mode and show status.
  help         Show this help.

Examples:
  scripts/pro_loop.ps1 -Command local -Root <project-root>
  scripts/pro_loop.ps1 -Command pro -Root <project-root> -TargetChatGptUrl https://chatgpt.com/...
  scripts/pro_loop.ps1 -Command testline -Root <project-root> -ConfirmTestlineIsolation
  scripts/pro_loop.ps1 -Command recon -Root <project-root> -ModuleGoal "add import workflow"
"@
}

function Read-JsonIfExists {
  param([string]$Path)
  if (-not (Test-Path -LiteralPath $Path)) { return $null }
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Show-Gain {
  param([string]$ProjectRoot)
  $base = Join-Path $ProjectRoot "docs\ai-review-loop"
  $state = Read-JsonIfExists (Join-Path $base "review-state.json")
  if (-not $state) {
    Write-Output "Pro Loop Gain"
    Write-Output "No loop ledger found. Run: scripts/pro_loop.ps1 -Command local -Root `"$ProjectRoot`""
    return
  }
  $evidenceCount = if ($state.evidence_records) { @($state.evidence_records).Count } else { 0 }
  $reviewCount = if ($state.captured_reviews) { @($state.captured_reviews).Count } else { 0 }
  $promptCount = if ($state.pending_prompts) { @($state.pending_prompts).Count } else { 0 }
  [pscustomobject]@{
    title = "Pro Loop Gain"
    pro_review_mode = $state.pro_review_mode
    loop_status = $state.loop_status
    goal_verdict = $state.goal_verdict
    should_send_to_gpt = $state.should_send_to_gpt
    send_reason = $state.send_reason
    local_only_next_action = $state.local_only_next_action
    evidence_records = $evidenceCount
    captured_reviews = $reviewCount
    pending_prompts = $promptCount
    auto_experience_count = $state.auto_experience_count
    suppressed_experience_count = $state.suppressed_experience_count
    done_gate_verdict = $state.done_gate_verdict
    completion_guard_status = $state.completion_guard_status
  } | Format-List
}

function Show-OrRecordDebt {
  param(
    [string]$ProjectRoot,
    [string]$Note,
    [string]$Trigger
  )
  $base = Join-Path $ProjectRoot "docs\ai-review-loop"
  $debtFile = Join-Path $base "pro-loop-debt.md"
  if ($Note) {
    New-Item -ItemType Directory -Path $base -Force | Out-Null
    if (-not (Test-Path -LiteralPath $debtFile)) {
      Set-Content -LiteralPath $debtFile -Encoding UTF8 -Value "# Pro Loop Debt`n"
    }
    $stamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $triggerText = if ($Trigger) { $Trigger } else { "before claiming project-total completion" }
    Add-Content -LiteralPath $debtFile -Encoding UTF8 -Value "`n- $stamp | note: $Note | trigger: $triggerText"
  }

  Write-Output "Pro Loop Debt"
  if (Test-Path -LiteralPath $debtFile) {
    Get-Content -LiteralPath $debtFile
  } else {
    Write-Output "No project debt ledger yet."
  }

  $skip = @(".git", "docs\ai-review-loop")
  $markers = @()
  Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $relative = [System.IO.Path]::GetRelativePath($ProjectRoot, $_.FullName)
      -not ($skip | Where-Object { $relative.StartsWith($_, [System.StringComparison]::OrdinalIgnoreCase) })
    } |
    ForEach-Object {
      try {
        Select-String -LiteralPath $_.FullName -Pattern "pro-loop:" -SimpleMatch -ErrorAction Stop | ForEach-Object {
          $markers += "{0}:{1}: {2}" -f [System.IO.Path]::GetRelativePath($ProjectRoot, $_.Path), $_.LineNumber, $_.Line.Trim()
        }
      } catch {}
    }
  if ($markers.Count) {
    Write-Output ""
    Write-Output "Inline pro-loop: markers"
    $markers | ForEach-Object { Write-Output $_ }
  }
}

$projectRoot = Resolve-LoopRoot $Root

switch ($Command) {
  "help" { Show-Help }
  "local" {
    & $MainScript -Action Init -Root $projectRoot -ProReviewMode disabled
    & $MainScript -Action RunLoop -Root $projectRoot
  }
  "off" {
    & $MainScript -Action Init -Root $projectRoot -ProReviewMode disabled
    & $MainScript -Action Status -Root $projectRoot
  }
  "pro" {
    if (-not $TargetChatGptUrl) { throw "TargetChatGptUrl is required for -Command pro." }
    & $MainScript -Action Init -Root $projectRoot -TargetChatGptUrl $TargetChatGptUrl -ProReviewMode optional
    & $MainScript -Action PrepareCompactReview -Root $projectRoot
  }
  "required-pro" {
    if (-not $TargetChatGptUrl) { throw "TargetChatGptUrl is required for -Command required-pro." }
    & $MainScript -Action Init -Root $projectRoot -TargetChatGptUrl $TargetChatGptUrl -ProReviewMode required
    & $MainScript -Action PrepareCompactReview -Root $projectRoot
  }
  "testline" {
    $configureArgs = @{
      Action = "ConfigureLoopProfile"
      Root = $projectRoot
      LoopProfile = "testline_95_auto"
      TargetScore = $TargetScore
    }
    if ($ConfirmTestlineIsolation) { $configureArgs.ConfirmTestlineIsolation = $true }
    & $MainScript @configureArgs
    & $MainScript -Action RunLoop -Root $projectRoot -GoalScope test_line
  }
  "status" { & $MainScript -Action Status -Root $projectRoot }
  "audit" {
    $capabilityArgs = @{
      Action = "RunCapabilityScan"
      Root = $projectRoot
    }
    if ($AuditContext) { $capabilityArgs.AuditContext = $AuditContext }
    & $MainScript @capabilityArgs
    & $MainScript -Action RunEfficiencyAudit -Root $projectRoot -PeriodicAudit
  }
  "recon" {
    $reconArgs = @{
      Action = "ReuseRecon"
      Root = $projectRoot
    }
    if ($ModuleGoal) { $reconArgs.ModuleGoal = $ModuleGoal }
    if ($ModuleCategory) { $reconArgs.ModuleCategory = $ModuleCategory }
    if ($AuditContext) { $reconArgs.AuditContext = $AuditContext }
    if ($AllowWebResearch) { $reconArgs.AllowWebResearch = $true }
    if ($AllowToolDiscovery) { $reconArgs.AllowToolDiscovery = $true }
    & $MainScript @reconArgs
  }
  "gain" { Show-Gain -ProjectRoot $projectRoot }
  "debt" { Show-OrRecordDebt -ProjectRoot $projectRoot -Note $DebtNote -Trigger $DebtTrigger }
}
