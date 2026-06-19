[CmdletBinding()]
param(
  [ValidateSet("Init", "Prepare", "SendPrompt", "CaptureFeedback", "CaptureReview", "WaitFeedback", "AssessFeedback", "SendAssessment", "NextDecision", "RunLoop", "RecordExperience", "Status", "Run")]
  [string]$Action = "Run",
  [string]$Root,
  [string]$TargetChatGptUrl,
  [string]$OpenedTabUrl,
  [switch]$AllowSensitive,
  [switch]$Send,
  [switch]$ForceBaseline,
  [ValidateSet("gpt-pro", "codex-efficiency-auditor")]
  [string]$Reviewer = "gpt-pro",
  [ValidateSet("initial", "recheck", "process-audit", "goal-audit")]
  [string]$Phase = "initial",
  [string]$ReviewText,
  [string]$ReviewFile,
  [string]$FeedbackText,
  [string]$FeedbackFile,
  [string]$AssessmentText,
  [string]$AssessmentFile,
  [ValidateSet("local-practice", "combined-next-decision")]
  [string]$AssessmentType = "combined-next-decision",
  [ValidateSet("GOAL_ACHIEVED", "CONTINUE", "NEEDS_EVIDENCE", "NEEDS_PROCESS_FIX", "NEEDS_HUMAN_DECISION", "BLOCKED")]
  [string]$GoalVerdict = "CONTINUE",
  [string]$NextAction = "collect_evidence",
  [string]$ExperienceOutcome = "unspecified",
  [string]$ExperienceLesson,
  [string]$ExperienceNotes
)

$ErrorActionPreference = "Stop"

if ($PSVersionTable.PSVersion.Major -lt 7) {
  throw "gpt_pro_review_loop.ps1 requires PowerShell 7+ because it uses .NET path APIs such as System.IO.Path.GetRelativePath."
}

# Deterministic local ledger for the offline review loop. Browser operations and
# Codex efficiency review happen outside this script; this script stores their
# results in one event stream and decides the next loop state.
$SkipDirectories = @(
  ".git", ".hg", ".svn", ".codegraph",
  "node_modules", ".venv", "venv", "__pycache__",
  "dist", "build", "target", ".next", ".cache",
  ".pytest_cache", ".mypy_cache", ".ruff_cache"
)

$SkipPathPrefixes = @(
  "docs/ai-review-loop"
)

function Resolve-ProjectRoot {
  param([string]$Candidate)
  if ($Candidate) { return (Resolve-Path -LiteralPath $Candidate).Path }
  try {
    $gitRoot = (& git -C (Get-Location).Path rev-parse --show-toplevel 2>$null)
    if ($LASTEXITCODE -eq 0 -and $gitRoot) {
      return (Resolve-Path -LiteralPath $gitRoot.Trim()).Path
    }
  } catch {
  } finally {
    $global:LASTEXITCODE = 0
  }
  return (Resolve-Path -LiteralPath (Get-Location).Path).Path
}

function ConvertTo-JsonFile {
  param(
    [Parameter(Mandatory = $true)]$Value,
    [Parameter(Mandatory = $true)][string]$Path
  )
  $dir = Split-Path -Parent $Path
  if ($dir -and -not (Test-Path -LiteralPath $dir)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Read-JsonFile {
  param([Parameter(Mandatory = $true)][string]$Path)
  return Get-Content -Raw -LiteralPath $Path | ConvertFrom-Json
}

function Set-ObjectProperty {
  param(
    [Parameter(Mandatory = $true)]$Object,
    [Parameter(Mandatory = $true)][string]$Name,
    $Value
  )
  if ($Object.PSObject.Properties.Name -contains $Name) {
    $Object.$Name = $Value
  } else {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
}

function Get-ReviewPaths {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $base = Join-Path $ProjectRoot "docs\ai-review-loop"
  return [pscustomobject]@{
    Base = $base
    Config = Join-Path $base "project-config.json"
    State = Join-Path $base "review-state.json"
    Decisions = Join-Path $base "decisions.md"
    Dossiers = Join-Path $base "dossiers"
    CodeMaps = Join-Path $base "code-maps"
    RoundRequests = Join-Path $base "round-requests"
    Prompts = Join-Path $base "prompts"
    Reviews = Join-Path $base "reviews"
    Assessments = Join-Path $base "assessments"
    LoopRuns = Join-Path $base "loop-runs"
    SecurityScans = Join-Path $base "security-scans"
    ExperienceLog = Join-Path $base "experience-log.md"
    ExperienceIssues = Join-Path $base "experience-issues"
  }
}

function Test-ChatGptUrl {
  param([string]$Url)
  return ($Url -and $Url.Trim() -match "^https://chatgpt\.com/")
}

function Get-RelativePath {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Path
  )
  if (-not $Root) { throw "Get-RelativePath received an empty Root." }
  if (-not $Path) { throw "Get-RelativePath received an empty Path." }
  return ([System.IO.Path]::GetRelativePath($Root, $Path) -replace "\\", "/")
}

function Get-State {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $paths = Get-ReviewPaths -ProjectRoot $ProjectRoot
  if (-not (Test-Path -LiteralPath $paths.State)) {
    throw "Missing review state. Run -Action Init first."
  }
  return Read-JsonFile $paths.State
}

function Save-State {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)]$State
  )
  $paths = Get-ReviewPaths -ProjectRoot $ProjectRoot
  Set-ObjectProperty $State "updated_at" (Get-Date).ToString("o")
  ConvertTo-JsonFile $State $paths.State
}

function Add-StateItem {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$Field,
    [Parameter(Mandatory = $true)][string]$Value
  )
  $state = Get-State $ProjectRoot
  if (-not ($state.PSObject.Properties.Name -contains $Field) -or $null -eq $state.$Field) {
    Set-ObjectProperty $state $Field @()
  }
  $items = @($state.$Field)
  if ($items -notcontains $Value) {
    Set-ObjectProperty $state $Field @($items + $Value)
  }
  Save-State $ProjectRoot $state
}

function Ensure-ReviewLoop {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$ChatUrl
  )
  $paths = Get-ReviewPaths -ProjectRoot $ProjectRoot
  foreach ($dir in @($paths.Base, $paths.Dossiers, $paths.CodeMaps, $paths.RoundRequests, $paths.Prompts, $paths.Reviews, $paths.Assessments, $paths.LoopRuns, $paths.SecurityScans, $paths.ExperienceIssues)) {
    if (-not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
  }
  if (-not (Test-Path -LiteralPath $paths.Decisions)) {
    Set-Content -LiteralPath $paths.Decisions -Encoding UTF8 -Value "# GPT Pro Review Loop Decisions`n"
  }
  if (-not (Test-Path -LiteralPath $paths.ExperienceLog)) {
    Set-Content -LiteralPath $paths.ExperienceLog -Encoding UTF8 -Value "# GPT Pro Review Loop Experience Log`n"
  }

  $targetUrl = if ($ChatUrl) { $ChatUrl.Trim() } else { $null }
  if ($targetUrl -and -not (Test-ChatGptUrl $targetUrl)) {
    throw "TargetChatGptUrl must be a https://chatgpt.com/... URL."
  }
  $previousTargetUrl = $null
  if (Test-Path -LiteralPath $paths.Config) {
    $config = Read-JsonFile $paths.Config
    $previousTargetUrl = $config.target_chatgpt_conversation_url
    if ($targetUrl) {
      Set-ObjectProperty $config "target_chatgpt_conversation_url" $targetUrl
      Set-ObjectProperty $config "target_chatgpt_url" $targetUrl
    }
  } else {
    $config = [ordered]@{
      target_chatgpt_conversation_url = $targetUrl
      target_chatgpt_url = $targetUrl
      transport = "browser_dossier"
      run_mode = "continuous_until_stopped"
      review_memory = "chatgpt_project_conversation"
      baseline_policy = "first_round_full_then_delta"
      sensitive_scan_policy = "block_unless_allow_sensitive"
      local_project_name = (Split-Path -Leaf $ProjectRoot)
    }
  }
  $requiredConfig = [ordered]@{
    transport = "browser_dossier"
    run_mode = "continuous_until_stopped"
    review_memory = "chatgpt_project_conversation"
    baseline_policy = "first_round_full_then_delta"
    sensitive_scan_policy = "block_unless_allow_sensitive"
    code_map_policy = "filesystem_map_with_optional_codegraph_context"
    codex_assessment_required = $true
    feedback_return_policy = "send_local_assessment_to_same_chat"
    url_selection_policy = "ask_once_when_missing_or_changed"
  }
  foreach ($key in $requiredConfig.Keys) {
    Set-ObjectProperty $config $key $requiredConfig[$key]
  }
  Set-ObjectProperty $config "local_project_name" (Split-Path -Leaf $ProjectRoot)
  ConvertTo-JsonFile $config $paths.Config

  if (-not (Test-Path -LiteralPath $paths.State)) {
    $state = [ordered]@{
      version = 3
      updated_at = (Get-Date).ToString("o")
      baseline_sent = $false
      baseline_hash = $null
      round_counter = 0
      iteration_counter = 0
      loop_mode = "continuous_until_stopped"
      loop_status = "idle"
      latest_prompt = $null
      latest_review = $null
      latest_assessment = $null
      goal_verdict = "CONTINUE"
      next_action = "prepare_review"
      stop_reason = $null
      pending_prompts = @()
      pending_reviews = @()
      captured_reviews = @()
      pending_assessments = @()
      target_chatgpt_conversation_url = $targetUrl
      baseline_sent_to_url = $null
      baseline_sent_hash = $null
      latest_prompt_target_url = $null
      latest_prompt_opened_tab_url = $null
      latest_assessment_target_url = $null
      latest_assessment_opened_tab_url = $null
      continuation_required = $false
      url_confirmation_required = -not (Test-ChatGptUrl $targetUrl)
      url_confirmation_reason = if (Test-ChatGptUrl $targetUrl) { $null } else { "missing_target_chatgpt_url" }
    }
  } else {
    $state = Read-JsonFile $paths.State
    foreach ($field in @("version", "iteration_counter", "loop_mode", "loop_status", "latest_review", "goal_verdict", "next_action", "stop_reason", "baseline_sent_to_url", "baseline_sent_hash", "latest_prompt_target_url", "latest_prompt_opened_tab_url", "latest_assessment_target_url", "latest_assessment_opened_tab_url", "continuation_required", "url_confirmation_required", "url_confirmation_reason")) {
      if (-not ($state.PSObject.Properties.Name -contains $field)) {
        $default = $null
        if ($field -eq "version") { $default = 3 }
        if ($field -eq "iteration_counter") { $default = 0 }
        if ($field -eq "loop_mode") { $default = "continuous_until_stopped" }
        if ($field -eq "loop_status") { $default = "idle" }
        if ($field -eq "goal_verdict") { $default = "CONTINUE" }
        if ($field -eq "next_action") { $default = "prepare_review" }
        if ($field -eq "continuation_required") { $default = $false }
        if ($field -eq "url_confirmation_required") { $default = $true }
        Set-ObjectProperty $state $field $default
      }
    }
    foreach ($field in @("pending_prompts", "pending_reviews", "captured_reviews", "pending_assessments")) {
      if (-not ($state.PSObject.Properties.Name -contains $field) -or $null -eq $state.$field) {
        Set-ObjectProperty $state $field @()
      }
    }
    Set-ObjectProperty $state "version" 3
    Set-ObjectProperty $state "loop_mode" "continuous_until_stopped"
    $stateTargetBefore = $state.target_chatgpt_conversation_url
    $configTarget = $config.target_chatgpt_conversation_url
    if (-not $configTarget) { $configTarget = $config.target_chatgpt_url }
    if ($configTarget) {
      Set-ObjectProperty $state "target_chatgpt_conversation_url" $configTarget
    }
    if (($targetUrl -and $previousTargetUrl -and $targetUrl -ne $previousTargetUrl) -or
      ($stateTargetBefore -and $configTarget -and $stateTargetBefore -ne $configTarget)) {
      Set-ObjectProperty $state "baseline_sent" $false
      Set-ObjectProperty $state "baseline_sent_to_url" $null
      Set-ObjectProperty $state "baseline_sent_hash" $null
      Set-ObjectProperty $state "next_action" "prepare_review"
      Set-ObjectProperty $state "url_confirmation_required" $true
      Set-ObjectProperty $state "url_confirmation_reason" "target_chatgpt_url_changed"
    }
  }
  if ($config.target_chatgpt_conversation_url -and $state.target_chatgpt_conversation_url -ne $config.target_chatgpt_conversation_url) {
    Set-ObjectProperty $state "target_chatgpt_conversation_url" $config.target_chatgpt_conversation_url
  }
  $effectiveTarget = $config.target_chatgpt_conversation_url
  if (-not $effectiveTarget) { $effectiveTarget = $config.target_chatgpt_url }
  if (Test-ChatGptUrl $effectiveTarget) {
    if ($targetUrl -or -not $state.url_confirmation_required -or $state.url_confirmation_reason -ne "target_chatgpt_url_changed") {
      Set-ObjectProperty $state "url_confirmation_required" $false
      Set-ObjectProperty $state "url_confirmation_reason" $null
    }
  } else {
    Set-ObjectProperty $state "url_confirmation_required" $true
    Set-ObjectProperty $state "url_confirmation_reason" "missing_target_chatgpt_url"
    Set-ObjectProperty $state "next_action" "confirm_target_chatgpt_url"
  }
  Save-State $ProjectRoot $state
  return $paths
}

function Assert-TargetChatGptUrl {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $config = Get-Config -ProjectRoot $ProjectRoot
  $state = Get-State -ProjectRoot $ProjectRoot
  $target = $config.target_chatgpt_conversation_url
  if (-not $target) { $target = $config.target_chatgpt_url }
  if ($state.url_confirmation_required) {
    $reason = if ($state.url_confirmation_reason) { $state.url_confirmation_reason } else { "target_chatgpt_url_needs_confirmation" }
    throw "Target ChatGPT URL requires one-time user confirmation ($reason). Ask the user once for this project's ChatGPT project/conversation URL, then run -Action Init -TargetChatGptUrl https://chatgpt.com/..."
  }
  if (-not (Test-ChatGptUrl $target)) {
    throw "Target ChatGPT URL is not configured. Ask the user once for this project's ChatGPT project/conversation URL, then run -Action Init -TargetChatGptUrl https://chatgpt.com/..."
  }
  return $target
}

function Get-Config {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $paths = Get-ReviewPaths $ProjectRoot
  if (-not (Test-Path -LiteralPath $paths.Config)) {
    throw "Missing project config. Run -Action Init -TargetChatGptUrl <chatgpt-url> first."
  }
  return Read-JsonFile $paths.Config
}

function Get-GitText {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string[]]$Args
  )
  try {
    $output = & git -C $ProjectRoot @Args 2>$null
    if ($LASTEXITCODE -eq 0) { return ($output -join "`n").Trim() }
  } catch {
  } finally {
    $global:LASTEXITCODE = 0
  }
  return ""
}

function Test-SkippedPath {
  param([Parameter(Mandatory = $true)][string]$RelativePath)
  $normalized = ($RelativePath -replace "\\", "/").TrimStart("/")
  foreach ($prefix in $SkipPathPrefixes) {
    $normalizedPrefix = ($prefix -replace "\\", "/").TrimEnd("/")
    if ($normalized -eq $normalizedPrefix -or $normalized.StartsWith("$normalizedPrefix/")) { return $true }
  }
  foreach ($part in ($normalized -split "/")) {
    if ($SkipDirectories -contains $part) { return $true }
  }
  return $false
}

function Get-ProjectFiles {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [int]$Limit = 500
  )
  return @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
      $relative = Get-RelativePath -Root $ProjectRoot -Path $_.FullName
      if (-not (Test-SkippedPath $relative)) {
        [pscustomobject]@{
          path = $relative
          length = $_.Length
          extension = $_.Extension.ToLowerInvariant()
          last_write_time = $_.LastWriteTime.ToString("o")
        }
      }
    } |
    Sort-Object path |
    Select-Object -First $Limit)
}

function Get-ProjectTreeText {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $items = @(Get-ChildItem -LiteralPath $ProjectRoot -Force -ErrorAction SilentlyContinue |
    Where-Object { -not ($SkipDirectories -contains $_.Name) } |
    Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name |
    Select-Object -First 100)
  if ($items.Count -eq 0) { return "(empty project root)" }
  return ($items | ForEach-Object {
    if ($_.PSIsContainer) { "[dir]  " + $_.Name } else { "[file] " + $_.Name }
  }) -join "`n"
}

function Get-KeyFiles {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $patterns = @("AGENTS.md", "README.md", "package.json", "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod", "tsconfig.json", "godot.project", "project.godot", "*.sln", "*.csproj")
  $found = New-Object System.Collections.Generic.List[string]
  foreach ($pattern in $patterns) {
    foreach ($item in @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force -Filter $pattern -ErrorAction SilentlyContinue | Select-Object -First 20)) {
      $relative = Get-RelativePath -Root $ProjectRoot -Path $item.FullName
      if (-not (Test-SkippedPath $relative)) { $found.Add($relative) | Out-Null }
    }
  }
  return @($found.ToArray() | Sort-Object -Unique)
}

function Get-TestHints {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $hints = New-Object System.Collections.Generic.List[string]
  $packagePath = Join-Path $ProjectRoot "package.json"
  if (Test-Path -LiteralPath $packagePath) {
    try {
      $pkg = Get-Content -Raw -LiteralPath $packagePath | ConvertFrom-Json
      if ($pkg.scripts) {
        foreach ($script in $pkg.scripts.PSObject.Properties) {
          if ($script.Name -match "test|lint|check|build") {
            $hints.Add(("npm script `{0}`: {1}" -f $script.Name, $script.Value)) | Out-Null
          }
        }
      }
    } catch {
    }
  }
  foreach ($candidate in @("pytest.ini", "pyproject.toml", "tox.ini", "Cargo.toml", "go.mod", "Makefile")) {
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot $candidate)) { $hints.Add("Detected $candidate") | Out-Null }
  }
  if ($hints.Count -eq 0) { $hints.Add("(no obvious test command discovered)") | Out-Null }
  return @($hints.ToArray())
}

function Get-ContentExcerpt {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$MaxChars = 6000
  )
  try {
    $fileInfo = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($fileInfo.Length -gt 524288) { return "(skipped: file larger than 512 KiB)" }
    $text = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
    if ($text.Length -gt $MaxChars) { return $text.Substring(0, $MaxChars) + "`n...(truncated)" }
    return $text
  } catch {
    return "(unreadable: $($_.Exception.Message))"
  }
}

function Invoke-SensitiveScan {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [switch]$Allow
  )
  $paths = Get-ReviewPaths $ProjectRoot
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $scanPath = Join-Path $paths.SecurityScans "$stamp-sensitive-scan.json"
  $riskyNames = @("^\.env($|\.)", "\.pem$", "\.key$", "id_rsa$", "id_dsa$", "cookies?\.txt$", "auth\.json$", "credentials?\.json$")
  $patterns = @(
    @{ name = "OpenAI-style API key"; pattern = "sk-[A-Za-z0-9_-]{20,}" },
    @{ name = "Private key header"; pattern = "-----BEGIN [A-Z ]*PRIVATE KEY-----" },
    @{ name = "Token/password assignment"; pattern = "(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|session[_-]?token|cookie|password)\s*[:=]\s*['""]?[^'""\s]{12,}" }
  )
  $issues = New-Object System.Collections.Generic.List[object]
  foreach ($file in @(Get-ProjectFiles $ProjectRoot 20000)) {
    $name = Split-Path -Leaf $file.path
    foreach ($rule in $riskyNames) {
      if ($name -match $rule) {
        $issues.Add([pscustomobject]@{ path = $file.path; type = "risky_filename"; rule = $rule }) | Out-Null
        break
      }
    }
    if ($file.length -gt 1048576) { continue }
    $fullPath = Join-Path $ProjectRoot ($file.path -replace "/", "\")
    try { $text = Get-Content -Raw -LiteralPath $fullPath -ErrorAction Stop } catch { continue }
    foreach ($rule in $patterns) {
      if ($text -match $rule.pattern) {
        $issues.Add([pscustomobject]@{ path = $file.path; type = "content_pattern"; rule = $rule.name }) | Out-Null
      }
    }
    if ($issues.Count -ge 50) { break }
  }
  $result = [ordered]@{
    created_at = (Get-Date).ToString("o")
    project_name = (Split-Path -Leaf $ProjectRoot)
    transport = "browser_dossier"
    basic_scan_only = $true
    excluded_paths = @($SkipPathPrefixes)
    issue_count = $issues.Count
    allowed = [bool]$Allow
    issues = @($issues.ToArray())
  }
  ConvertTo-JsonFile $result $scanPath
  if ($issues.Count -gt 0 -and -not $Allow) {
    Write-Host "Sensitive-data scan failed. Review this file:" -ForegroundColor Red
    Write-Host $scanPath
    foreach ($issue in @($issues | Select-Object -First 10)) {
      Write-Host (" - {0}: {1}" -f $issue.path, $issue.rule) -ForegroundColor Red
    }
    throw "Sensitive-data scan blocked the review. Re-run with -AllowSensitive only after explicit user authorization."
  }
  Write-Host "Sensitive-data scan passed: $scanPath" -ForegroundColor Green
  return $scanPath
}

function New-ProjectDossier {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ScanPath,
    [Parameter(Mandatory = $true)][string]$RoundId
  )
  $paths = Get-ReviewPaths $ProjectRoot
  $dossierPath = Join-Path $paths.Dossiers "$RoundId-project-dossier.md"
  $projectName = Split-Path -Leaf $ProjectRoot
  $branch = Get-GitText $ProjectRoot @("branch", "--show-current")
  if (-not $branch) { $branch = "(not a git repo or detached)" }
  $gitStatus = Get-GitText $ProjectRoot @("status", "--short")
  if (-not $gitStatus) { $gitStatus = "(clean, not a git repo, or unavailable)" }
  $recentCommits = Get-GitText $ProjectRoot @("log", "--oneline", "-8")
  if (-not $recentCommits) { $recentCommits = "(not available)" }
  $keyFiles = Get-KeyFiles $ProjectRoot
  if ($keyFiles.Count -eq 0) { $keyFiles = @("(none discovered)") }
  $tests = Get-TestHints $ProjectRoot
  $scanRel = Get-RelativePath -Root $ProjectRoot -Path $ScanPath
  $body = @"
# Project Dossier

- id: $RoundId-dossier
- created_at: $(Get-Date -Format o)
- source: codex
- transport: browser_dossier
- status: baseline_material
- project_name: $projectName

## Use

This dossier is a sanitized baseline for offline review. Treat paths as project-relative. Ask Codex for missing snippets or command output.

## Project Snapshot

- branch: $branch
- security_scan: $scanRel

## Top-Level Layout

```text
$(Get-ProjectTreeText $ProjectRoot)
```

## Key Files And Manifests

```text
$($keyFiles -join "`n")
```

## Test And Verification Hints

```text
$($tests -join "`n")
```

## Git Status

```text
$gitStatus
```

## Recent Commits

```text
$recentCommits
```

"@
  Set-Content -LiteralPath $dossierPath -Encoding UTF8 -Value $body
  return $dossierPath
}

function New-CodeMap {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$RoundId
  )
  $paths = Get-ReviewPaths -ProjectRoot $ProjectRoot
  $codeMapPath = Join-Path $paths.CodeMaps "$RoundId-code-map.md"
  $files = @(Get-ProjectFiles $ProjectRoot 1200)
  $byExt = @($files | Group-Object extension | Sort-Object Count -Descending | Select-Object -First 20 | ForEach-Object {
    $name = if ($_.Name) { $_.Name } else { "(no extension)" }
    "{0}: {1}" -f $name, $_.Count
  })
  if ($byExt.Count -eq 0) { $byExt = @("(no files)") }
  $important = @($files | Where-Object {
    $_.path -match "(^|/)(src|app|lib|server|client|tests?|spec|docs|scripts|tools)/" -or
    $_.path -match "(AGENTS|README|package|pyproject|Cargo|go\.mod|tsconfig|vite|next|godot|project)\."
  } | Select-Object -First 300)
  if ($important.Count -eq 0) { $important = @($files | Select-Object -First 120) }
  $fileLines = @($important | ForEach-Object { "- {0} ({1} bytes)" -f $_.path, $_.length })
  if ($fileLines.Count -eq 0) { $fileLines = @("- (no project files discovered)") }
  $diffSummary = Get-GitText $ProjectRoot @("diff", "--stat")
  if (-not $diffSummary) { $diffSummary = "(no unstaged diff stat or unavailable)" }
  $bodyLines = @(
    "# Code Map",
    "",
    "- id: $RoundId-code-map",
    "- created_at: $(Get-Date -Format o)",
    "- source: codex",
    "- transport: browser_dossier",
    "- status: code_map",
    "",
    "## File Type Summary",
    "",
    '```text',
    ($byExt -join "`n"),
    '```',
    "",
    "## Important Project Files",
    "",
    ($fileLines -join "`n"),
    "",
    "## Working Tree Diff Stat",
    "",
    '```text',
    $diffSummary,
    '```'
  )
  Set-Content -LiteralPath $codeMapPath -Encoding UTF8 -Value ($bodyLines -join [Environment]::NewLine)
  return $codeMapPath
}

function New-RoundRequest {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$RoundId,
    [Parameter(Mandatory = $true)][string]$ScanPath
  )
  $paths = Get-ReviewPaths -ProjectRoot $ProjectRoot
  $requestPath = Join-Path $paths.RoundRequests "$RoundId-round-request.md"
  $gitStatus = Get-GitText $ProjectRoot @("status", "--short")
  if (-not $gitStatus) { $gitStatus = "(clean, not a git repo, or unavailable)" }
  $diffStat = Get-GitText $ProjectRoot @("diff", "--stat")
  if (-not $diffStat) { $diffStat = "(no unstaged diff stat or unavailable)" }
  $scanRel = Get-RelativePath -Root $ProjectRoot -Path $ScanPath
  $bodyLines = @(
    "# Review Request",
    "",
    "- id: $RoundId-request",
    "- created_at: $(Get-Date -Format o)",
    "- source: codex",
    "- transport: browser_dossier",
    "- status: ready_for_review",
    "- security_scan: $scanRel",
    "",
    "## Requested Review",
    "",
    "Review this round with the conversation baseline and material below. GPT Pro should focus on product/technical risks. Codex efficiency auditor should focus on process quality and whether the total goal is achieved.",
    "",
    "## Local Changes Since Last Review",
    "",
    '```text',
    $gitStatus,
    '```',
    "",
    "## Diff Stat",
    "",
    '```text',
    $diffStat,
    '```'
  )
  Set-Content -LiteralPath $requestPath -Encoding UTF8 -Value ($bodyLines -join [Environment]::NewLine)
  return $requestPath
}

function Get-FileHashText {
  param([string[]]$Paths)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $builder = New-Object System.Text.StringBuilder
  foreach ($path in $Paths) {
    if (Test-Path -LiteralPath $path) { [void]$builder.AppendLine((Get-Content -Raw -LiteralPath $path)) }
  }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
  return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
}

function New-ReviewPrompt {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$RoundId,
    [Parameter(Mandatory = $true)][string]$DossierPath,
    [Parameter(Mandatory = $true)][string]$CodeMapPath,
    [Parameter(Mandatory = $true)][string]$RequestPath,
    [Parameter(Mandatory = $true)][string]$BaselineHash,
    [switch]$ForceFullBaseline
  )
  $paths = Get-ReviewPaths -ProjectRoot $ProjectRoot
  $config = Get-Config -ProjectRoot $ProjectRoot
  $state = Get-State -ProjectRoot $ProjectRoot
  if (-not $paths.Prompts) { throw "Review path set is missing Prompts directory." }
  if (-not (Test-Path -LiteralPath $paths.Prompts)) {
    New-Item -ItemType Directory -Path $paths.Prompts -Force | Out-Null
  }
  $promptPath = [System.IO.Path]::Combine([string]$paths.Prompts, "$RoundId-review-prompt.md")
  if (-not $promptPath) { throw "Could not build review prompt path." }
  $target = $config.target_chatgpt_conversation_url
  if (-not $target) { $target = $config.target_chatgpt_url }
  $includeBaseline = [bool]$ForceFullBaseline -or
    -not [bool]$state.baseline_sent -or
    $state.baseline_sent_to_url -ne $target -or
    $state.baseline_sent_hash -ne $BaselineHash
  $baselineNote = if ($includeBaseline) {
    "Full baseline is included because this is the first send, target/hash changed, or -ForceBaseline was requested."
  } else {
    "Baseline already sent to this ChatGPT conversation with the same baseline hash; this round is delta-only."
  }
  $dossier = if ($includeBaseline) { Get-ContentExcerpt $DossierPath 18000 } else { "(baseline already sent in this ChatGPT conversation with matching hash)" }
  $codeMap = if ($includeBaseline) { Get-ContentExcerpt $CodeMapPath 22000 } else { "(baseline code map already sent; this round is delta-only)" }
  $request = Get-ContentExcerpt $RequestPath 18000
  $prompt = @"
You are GPT Pro reviewing a Codex project through an offline review loop.

Use only the project baseline and round material in this ChatGPT conversation. Ask Codex for missing snippets or command output.

Codex will also run a local Codex efficiency auditor review. Your feedback and the efficiency review will be merged into a local assessment and next decision.

## Round

$RoundId

## Baseline State

- baseline_hash: $BaselineHash
- target_chatgpt_url: $target
- baseline_mode: $baselineNote

## Baseline Dossier

$dossier

## Code Map

$codeMap

## Round Request

$request
"@
  $promptOutputPath = [System.IO.Path]::Combine([string]$paths.Prompts, "$RoundId-review-prompt.md")
  if (-not $promptOutputPath) { throw "Could not build review prompt output path." }
  Set-Content -LiteralPath $promptOutputPath -Encoding UTF8 -Value $prompt
  $rel = Get-RelativePath -Root $ProjectRoot -Path $promptOutputPath
  Set-ObjectProperty $state "latest_prompt" $rel
  Add-StateItem -ProjectRoot $ProjectRoot -Field "pending_prompts" -Value $rel
  return $promptOutputPath
}

function New-ReviewPackage {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ScanPath,
    [switch]$ForceFullBaseline
  )
  $state = Get-State -ProjectRoot $ProjectRoot
  $roundNumber = [int]$state.round_counter + 1
  $iterationNumber = [int]$state.iteration_counter + 1
  $roundId = "round-{0:000}-iter-{1:000}-{2}" -f $roundNumber, $iterationNumber, (Get-Date -Format "yyyyMMdd-HHmmss")
  $dossierPath = New-ProjectDossier -ProjectRoot $ProjectRoot -ScanPath $ScanPath -RoundId $roundId
  $codeMapPath = New-CodeMap -ProjectRoot $ProjectRoot -RoundId $roundId
  $requestPath = New-RoundRequest -ProjectRoot $ProjectRoot -RoundId $roundId -ScanPath $ScanPath
  $baselineHash = Get-FileHashText -Paths @($dossierPath, $codeMapPath)
  $promptPath = New-ReviewPrompt -ProjectRoot $ProjectRoot -RoundId $roundId -DossierPath $dossierPath -CodeMapPath $codeMapPath -RequestPath $requestPath -BaselineHash $baselineHash -ForceFullBaseline:$ForceFullBaseline
  $state = Get-State -ProjectRoot $ProjectRoot
  Set-ObjectProperty $state "round_counter" $roundNumber
  Set-ObjectProperty $state "iteration_counter" $iterationNumber
  Set-ObjectProperty $state "baseline_hash" $baselineHash
  Set-ObjectProperty $state "latest_dossier" (Get-RelativePath -Root $ProjectRoot -Path $dossierPath)
  Set-ObjectProperty $state "latest_code_map" (Get-RelativePath -Root $ProjectRoot -Path $codeMapPath)
  Set-ObjectProperty $state "latest_round_request" (Get-RelativePath -Root $ProjectRoot -Path $requestPath)
  Set-ObjectProperty $state "latest_prompt" (Get-RelativePath -Root $ProjectRoot -Path $promptPath)
  Set-ObjectProperty $state "loop_status" "running"
  Set-ObjectProperty $state "next_action" "send_or_capture_review"
  Save-State $ProjectRoot $state
  Write-Host "Review package created:" -ForegroundColor Green
  Write-Host "  Dossier: $dossierPath"
  Write-Host "  Code map: $codeMapPath"
  Write-Host "  Round request: $requestPath"
  Write-Host "  Prompt: $promptPath"
  return $promptPath
}

function Complete-PromptSend {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$PromptPath,
    [string]$ActualTabUrl
  )
  $config = Get-Config -ProjectRoot $ProjectRoot
  $state = Get-State $ProjectRoot
  $target = $config.target_chatgpt_conversation_url
  if (-not $target) { $target = $config.target_chatgpt_url }
  if ($ActualTabUrl -and -not (Test-ChatGptUrl $ActualTabUrl)) {
    throw "-OpenedTabUrl must be a https://chatgpt.com/... URL."
  }
  Set-ObjectProperty $state "baseline_sent" $true
  Set-ObjectProperty $state "baseline_sent_to_url" $target
  Set-ObjectProperty $state "baseline_sent_hash" $state.baseline_hash
  Set-ObjectProperty $state "latest_prompt" (Get-RelativePath -Root $ProjectRoot -Path $PromptPath)
  Set-ObjectProperty $state "latest_prompt_target_url" $target
  Set-ObjectProperty $state "latest_prompt_opened_tab_url" $ActualTabUrl
  Set-ObjectProperty $state "latest_prompt_sent_at" (Get-Date).ToString("o")
  Set-ObjectProperty $state "next_action" "capture_gpt_pro_review"
  Save-State $ProjectRoot $state
}

function Show-PromptHandoff {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [switch]$MarkSent
  )
  $config = Get-Config $ProjectRoot
  $state = Get-State $ProjectRoot
  if (-not $state.latest_prompt) { throw "No prompt is prepared. Run -Action Prepare first." }
  $promptPath = Join-Path $ProjectRoot ($state.latest_prompt -replace "/", "\")
  if (-not (Test-Path -LiteralPath $promptPath)) { throw "Prepared prompt does not exist: $promptPath" }
  $target = $config.target_chatgpt_conversation_url
  if (-not $target) { $target = $config.target_chatgpt_url }
  if (-not (Test-ChatGptUrl $target)) { throw "project-config.json needs a https://chatgpt.com/... URL." }
  Write-Host "Open this ChatGPT target with the edge-browser-control skill:" -ForegroundColor Cyan
  Write-Host $target
  Write-Host "If Edge is open but no ChatGPT conversation page is available, navigate the current or a fresh Edge tab to this URL." -ForegroundColor Yellow
  Write-Host "Paste or send this prompt file:" -ForegroundColor Cyan
  Write-Host $promptPath
  Write-Host "Offline browser dossier only. No local service or public network route is used." -ForegroundColor Green
  if ($MarkSent) {
    Complete-PromptSend $ProjectRoot $promptPath $OpenedTabUrl
    Write-Host "Marked prompt as sent." -ForegroundColor Green
  } else {
    Write-Host "After Edge submits it, rerun SendPrompt with -Send to mark it as sent. Add -OpenedTabUrl <actual-chatgpt-tab-url> when available." -ForegroundColor Yellow
  }
}

function Get-LatestFile {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [string]$Filter = "*.md"
  )
  if (-not (Test-Path -LiteralPath $Directory)) { return $null }
  return Get-ChildItem -LiteralPath $Directory -File -Filter $Filter -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Save-Review {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$ReviewerName,
    [Parameter(Mandatory = $true)][string]$ReviewPhase,
    [string]$Text,
    [string]$File
  )
  $paths = Get-ReviewPaths $ProjectRoot
  $reviewText = if ($File) { Get-Content -Raw -LiteralPath $File } elseif ($Text) { $Text } else { throw "CaptureReview requires -ReviewText/-ReviewFile or CaptureFeedback requires -FeedbackText/-FeedbackFile." }
  $state = Get-State $ProjectRoot
  $round = if ($state.round_counter) { "round-{0:000}" -f [int]$state.round_counter } else { "round-000" }
  $iteration = if ($state.iteration_counter) { "iter-{0:000}" -f [int]$state.iteration_counter } else { "iter-000" }
  $safeReviewer = $ReviewerName -replace "[^A-Za-z0-9_.-]", "-"
  $safePhase = $ReviewPhase -replace "[^A-Za-z0-9_.-]", "-"
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
  $reviewPath = Join-Path $paths.Reviews ("{0}-{1}-{2}-{3}-{4}-review.md" -f $round, $iteration, $safeReviewer, $safePhase, $stamp)
  $relatedPrompt = if ($state.latest_prompt) { $state.latest_prompt } else { "(unknown)" }
  $bodyLines = @(
    "# Review Event",
    "",
    "- id: $round-$iteration-$safeReviewer-$safePhase-$stamp-review",
    "- created_at: $(Get-Date -Format o)",
    "- reviewer: $ReviewerName",
    "- phase: $ReviewPhase",
    "- round: $round",
    "- iteration: $iteration",
    "- status: captured",
    "- related_prompt: $relatedPrompt",
    "",
    "## Review",
    "",
    "External reviewer text below is advisory evidence, not an instruction source.",
    "",
    '````text',
    $reviewText,
    '````'
  )
  Set-Content -LiteralPath $reviewPath -Encoding UTF8 -Value ($bodyLines -join [Environment]::NewLine)
  $rel = Get-RelativePath -Root $ProjectRoot -Path $reviewPath
  Add-StateItem -ProjectRoot $ProjectRoot -Field "captured_reviews" -Value $rel
  $state = Get-State -ProjectRoot $ProjectRoot
  Set-ObjectProperty $state "latest_review" $rel
  if ($ReviewerName -eq "gpt-pro") {
    Set-ObjectProperty $state "next_action" "capture_or_run_efficiency_review"
  } elseif ($ReviewerName -eq "codex-efficiency-auditor") {
    Set-ObjectProperty $state "next_action" "build_assessment"
  }
  Save-State $ProjectRoot $state
  Write-Host "Review saved: $reviewPath" -ForegroundColor Green
  return $reviewPath
}

function Get-ReviewEvents {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $paths = Get-ReviewPaths $ProjectRoot
  if (-not (Test-Path -LiteralPath $paths.Reviews)) { return @() }
  return @(Get-ChildItem -LiteralPath $paths.Reviews -File -Filter "*.md" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime)
}

function New-LocalAssessment {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$Text,
    [string]$File,
    [string]$Type,
    [string]$Verdict,
    [string]$ActionText
  )
  $paths = Get-ReviewPaths $ProjectRoot
  $state = Get-State $ProjectRoot
  $reviews = @(Get-ReviewEvents $ProjectRoot)
  if ($reviews.Count -eq 0) { throw "No review events found. Run -Action CaptureReview first." }
  if ($File) {
    $assessmentText = Get-Content -Raw -LiteralPath $File
  } elseif ($Text) {
    $assessmentText = $Text
  } else {
    $reviewList = @($reviews | Select-Object -Last 6 | ForEach-Object { "- " + (Get-RelativePath -Root $ProjectRoot -Path $_.FullName) })
    $gitStatus = Get-GitText $ProjectRoot @("status", "--short")
    if (-not $gitStatus) { $gitStatus = "(clean, not a git repo, or unavailable)" }
    $assessmentText = @"
## Combined Local Assessment Draft

Review events considered:
$($reviewList -join "`n")

## Local Evidence Snapshot

```text
$gitStatus
```

## Assessment Table

| Review item | Codex decision | Local evidence | Action |
|---|---|---|---|
| (fill from latest reviews) | needs-more-info | (cite local code/test/constraint) | (collect evidence or continue) |

## Goal And Process Judgment

- Goal verdict: $Verdict
- Next action: $ActionText
"@
  }
  $round = if ($state.round_counter) { "round-{0:000}" -f [int]$state.round_counter } else { "round-000" }
  $iteration = if ($state.iteration_counter) { "iter-{0:000}" -f [int]$state.iteration_counter } else { "iter-000" }
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss-fff"
  $assessmentPath = Join-Path $paths.Assessments ("{0}-{1}-{2}-{3}-assessment.md" -f $round, $iteration, $Type, $stamp)
  $body = @"
# Assessment Event

- id: $round-$iteration-$Type-$stamp-assessment
- created_at: $(Get-Date -Format o)
- source: codex
- assessment_type: $Type
- goal_verdict: $Verdict
- next_action: $ActionText
- status: ready_for_next_decision

$assessmentText
"@
  Set-Content -LiteralPath $assessmentPath -Encoding UTF8 -Value $body
  $rel = Get-RelativePath -Root $ProjectRoot -Path $assessmentPath
  Add-StateItem -ProjectRoot $ProjectRoot -Field "pending_assessments" -Value $rel
  $state = Get-State -ProjectRoot $ProjectRoot
  Set-ObjectProperty $state "latest_assessment" $rel
  Set-ObjectProperty $state "goal_verdict" $Verdict
  Set-ObjectProperty $state "next_action" $ActionText
  Save-State $ProjectRoot $state
  Write-Host "Assessment saved: $assessmentPath" -ForegroundColor Green
  return $assessmentPath
}

function New-AssessmentPrompt {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $paths = Get-ReviewPaths $ProjectRoot
  $config = Get-Config $ProjectRoot
  $state = Get-State $ProjectRoot
  if (-not $state.latest_assessment) { throw "No assessment found. Run -Action AssessFeedback first." }
  $assessmentPath = Join-Path $ProjectRoot ($state.latest_assessment -replace "/", "\")
  if (-not (Test-Path -LiteralPath $assessmentPath)) { throw "Assessment file does not exist: $assessmentPath" }
  $target = $config.target_chatgpt_conversation_url
  if (-not $target) { $target = $config.target_chatgpt_url }
  if (-not (Test-ChatGptUrl $target)) { throw "project-config.json needs a https://chatgpt.com/... URL." }
  $round = if ($state.round_counter) { "round-{0:000}" -f [int]$state.round_counter } else { "round-000" }
  $iteration = if ($state.iteration_counter) { "iter-{0:000}" -f [int]$state.iteration_counter } else { "iter-000" }
  $promptPath = Join-Path $paths.Prompts ("{0}-{1}-assessment-return-prompt.md" -f $round, $iteration)
  $assessment = Get-ContentExcerpt $assessmentPath 24000
  $prompt = @"
Codex has merged project review, local evidence, and Codex efficiency review into one assessment.

Please recheck this assessment, correct any recommendation that no longer fits, and identify the next narrow review question if another loop iteration is useful.

## Combined Assessment

$assessment
"@
  Set-Content -LiteralPath $promptPath -Encoding UTF8 -Value $prompt
  Set-ObjectProperty $state "latest_assessment_prompt" (Get-RelativePath -Root $ProjectRoot -Path $promptPath)
  Save-State $ProjectRoot $state
  Write-Host "Open this ChatGPT target with the edge-browser-control skill:" -ForegroundColor Cyan
  Write-Host $target
  Write-Host "If Edge is open but no ChatGPT conversation page is available, navigate the current or a fresh Edge tab to this URL." -ForegroundColor Yellow
  Write-Host "Send this assessment-return prompt:" -ForegroundColor Cyan
  Write-Host $promptPath
  if ($Send) {
    if ($OpenedTabUrl -and -not (Test-ChatGptUrl $OpenedTabUrl)) {
      throw "-OpenedTabUrl must be a https://chatgpt.com/... URL."
    }
    Set-ObjectProperty $state "latest_assessment_sent_at" (Get-Date).ToString("o")
    Set-ObjectProperty $state "latest_assessment_target_url" $target
    Set-ObjectProperty $state "latest_assessment_opened_tab_url" $OpenedTabUrl
    Set-ObjectProperty $state "next_action" "capture_gpt_pro_recheck"
    Save-State $ProjectRoot $state
    Write-Host "Marked assessment as sent." -ForegroundColor Green
  } else {
    Write-Host "After Edge submits it, rerun SendAssessment with -Send to mark it as sent. Add -OpenedTabUrl <actual-chatgpt-tab-url> when available." -ForegroundColor Yellow
  }
}

function Invoke-NextDecision {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $paths = Get-ReviewPaths $ProjectRoot
  $state = Get-State $ProjectRoot
  $verdict = if ($state.goal_verdict) { [string]$state.goal_verdict } else { "CONTINUE" }
  $status = "running"
  $stopReason = $null
  switch ($verdict) {
    "GOAL_ACHIEVED" { $status = "complete"; $stopReason = "goal_achieved" }
    "NEEDS_HUMAN_DECISION" { $status = "paused"; $stopReason = "human_decision_required" }
    "BLOCKED" { $status = "blocked"; $stopReason = "blocked_by_assessment" }
    default { $status = "running" }
  }
  Set-ObjectProperty $state "loop_status" $status
  Set-ObjectProperty $state "stop_reason" $stopReason
  Set-ObjectProperty $state "continuation_required" ($status -eq "running")
  Save-State $ProjectRoot $state
  $iteration = if ($state.iteration_counter) { "iter-{0:000}" -f [int]$state.iteration_counter } else { "iter-000" }
  $runPath = Join-Path $paths.LoopRuns ("{0}-{1}-loop-run.json" -f (Get-Date -Format "yyyyMMdd-HHmmss"), $iteration)
  $summary = [ordered]@{
    created_at = (Get-Date).ToString("o")
    iteration = $state.iteration_counter
    loop_status = $status
    goal_verdict = $verdict
    next_action = $state.next_action
    stop_reason = $stopReason
    continuation_required = ($status -eq "running")
    latest_prompt = $state.latest_prompt
    latest_review = $state.latest_review
    latest_assessment = $state.latest_assessment
  }
  ConvertTo-JsonFile $summary $runPath
  Write-Host "Next decision: $verdict" -ForegroundColor Green
  Write-Host "Loop status: $status"
  if ($status -eq "running") {
    Write-Host "Continuation required: do not stop the review loop here. Execute next_action, then prepare/send the next review event unless the user stops the session or a hard blocker appears." -ForegroundColor Yellow
  }
  Write-Host "Loop run record: $runPath"
}

function New-ExperienceRecord {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$Outcome,
    [string]$Lesson,
    [string]$Notes
  )
  Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $null | Out-Null
  $paths = Get-ReviewPaths -ProjectRoot $ProjectRoot
  $state = Get-State -ProjectRoot $ProjectRoot
  $stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
  $safeOutcome = if ($Outcome) { $Outcome } else { "unspecified" }
  $safeLesson = if ($Lesson) { $Lesson } else { "(fill in the reusable lesson)" }
  $safeNotes = if ($Notes) { $Notes } else { "(fill in what happened, without secrets or private data)" }
  $entry = @(
    "",
    "## $stamp",
    "",
    "- outcome: $safeOutcome",
    "- latest_review: $($state.latest_review)",
    "- latest_assessment: $($state.latest_assessment)",
    "- goal_verdict: $($state.goal_verdict)",
    "",
    "### Notes",
    "",
    $safeNotes,
    "",
    "### Reusable Lesson",
    "",
    $safeLesson
  ) -join [Environment]::NewLine
  Add-Content -LiteralPath $paths.ExperienceLog -Encoding UTF8 -Value $entry
  $issuePath = Join-Path $paths.ExperienceIssues ("{0}-github-issue-draft.md" -f $stamp)
  Set-Content -LiteralPath $issuePath -Encoding UTF8 -Value "# [experience] review event loop - $safeOutcome`n`n$safeNotes`n`n## Reusable lesson`n`n$safeLesson`n"
  Write-Host "Experience recorded: $($paths.ExperienceLog)" -ForegroundColor Green
  Write-Host "GitHub issue draft created: $issuePath" -ForegroundColor Green
}

function Show-Status {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $paths = Get-ReviewPaths $ProjectRoot
  $config = if (Test-Path -LiteralPath $paths.Config) { Read-JsonFile $paths.Config } else { $null }
  $state = if (Test-Path -LiteralPath $paths.State) { Read-JsonFile $paths.State } else { $null }
  [pscustomobject]@{
    project_name = (Split-Path -Leaf $ProjectRoot)
    review_loop_exists = (Test-Path -LiteralPath $paths.Base)
    transport = if ($config) { $config.transport } else { $null }
    target_chatgpt_url = if ($config) { if ($config.target_chatgpt_conversation_url) { $config.target_chatgpt_conversation_url } else { $config.target_chatgpt_url } } else { $null }
    loop_mode = if ($state) { $state.loop_mode } else { $null }
    loop_status = if ($state) { $state.loop_status } else { $null }
    round_counter = if ($state) { $state.round_counter } else { 0 }
    iteration_counter = if ($state) { $state.iteration_counter } else { 0 }
    latest_prompt = if ($state) { $state.latest_prompt } else { $null }
    latest_review = if ($state) { $state.latest_review } else { $null }
    latest_assessment = if ($state) { $state.latest_assessment } else { $null }
    baseline_sent = if ($state) { $state.baseline_sent } else { $false }
    baseline_sent_to_url = if ($state) { $state.baseline_sent_to_url } else { $null }
    baseline_sent_hash = if ($state) { $state.baseline_sent_hash } else { $null }
    latest_prompt_target_url = if ($state) { $state.latest_prompt_target_url } else { $null }
    latest_prompt_opened_tab_url = if ($state) { $state.latest_prompt_opened_tab_url } else { $null }
    latest_assessment_target_url = if ($state) { $state.latest_assessment_target_url } else { $null }
    latest_assessment_opened_tab_url = if ($state) { $state.latest_assessment_opened_tab_url } else { $null }
    continuation_required = if ($state) { $state.continuation_required } else { $false }
    url_confirmation_required = if ($state) { $state.url_confirmation_required } else { $null }
    url_confirmation_reason = if ($state) { $state.url_confirmation_reason } else { $null }
    pending_prompt_count = if ($state -and $state.pending_prompts) { @($state.pending_prompts).Count } else { 0 }
    captured_review_count = if ($state -and $state.captured_reviews) { @($state.captured_reviews).Count } else { 0 }
    goal_verdict = if ($state) { $state.goal_verdict } else { $null }
    next_action = if ($state) { $state.next_action } else { $null }
    stop_reason = if ($state) { $state.stop_reason } else { $null }
    config_path = $paths.Config
    state_path = $paths.State
  } | Format-List
}

$ProjectRoot = Resolve-ProjectRoot $Root

switch ($Action) {
  "Init" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    Write-Host "GPT Pro review loop initialized for project: $(Split-Path -Leaf $ProjectRoot)" -ForegroundColor Green
  }
  "Prepare" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    Assert-TargetChatGptUrl -ProjectRoot $ProjectRoot | Out-Null
    $scan = Invoke-SensitiveScan -ProjectRoot $ProjectRoot -Allow:$AllowSensitive
    New-ReviewPackage -ProjectRoot $ProjectRoot -ScanPath $scan -ForceFullBaseline:$ForceBaseline | Out-Null
  }
  "SendPrompt" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    Assert-TargetChatGptUrl -ProjectRoot $ProjectRoot | Out-Null
    Show-PromptHandoff -ProjectRoot $ProjectRoot -MarkSent:$Send
  }
  "CaptureFeedback" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    $text = if ($FeedbackText) { $FeedbackText } else { $ReviewText }
    $file = if ($FeedbackFile) { $FeedbackFile } else { $ReviewFile }
    Save-Review -ProjectRoot $ProjectRoot -ReviewerName "gpt-pro" -ReviewPhase "initial" -Text $text -File $file | Out-Null
  }
  "CaptureReview" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    Save-Review -ProjectRoot $ProjectRoot -ReviewerName $Reviewer -ReviewPhase $Phase -Text $ReviewText -File $ReviewFile | Out-Null
  }
  "WaitFeedback" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    $paths = Get-ReviewPaths -ProjectRoot $ProjectRoot
    $latest = Get-LatestFile $paths.Reviews
    if (-not $latest) { throw "No review has been captured yet. Use -Action CaptureReview." }
    Write-Host "Latest captured review: $($latest.FullName)" -ForegroundColor Green
  }
  "AssessFeedback" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    New-LocalAssessment -ProjectRoot $ProjectRoot -Text $AssessmentText -File $AssessmentFile -Type $AssessmentType -Verdict $GoalVerdict -ActionText $NextAction | Out-Null
  }
  "SendAssessment" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    Assert-TargetChatGptUrl -ProjectRoot $ProjectRoot | Out-Null
    New-AssessmentPrompt -ProjectRoot $ProjectRoot
  }
  "NextDecision" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    Invoke-NextDecision -ProjectRoot $ProjectRoot
  }
  "RunLoop" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    Assert-TargetChatGptUrl -ProjectRoot $ProjectRoot | Out-Null
    $scan = Invoke-SensitiveScan -ProjectRoot $ProjectRoot -Allow:$AllowSensitive
    New-ReviewPackage -ProjectRoot $ProjectRoot -ScanPath $scan -ForceFullBaseline:$ForceBaseline | Out-Null
    Show-PromptHandoff -ProjectRoot $ProjectRoot -MarkSent:$Send
  }
  "RecordExperience" {
    New-ExperienceRecord -ProjectRoot $ProjectRoot -Outcome $ExperienceOutcome -Lesson $ExperienceLesson -Notes $ExperienceNotes
  }
  "Status" {
    Show-Status -ProjectRoot $ProjectRoot
  }
  "Run" {
    Ensure-ReviewLoop -ProjectRoot $ProjectRoot -ChatUrl $TargetChatGptUrl | Out-Null
    Assert-TargetChatGptUrl -ProjectRoot $ProjectRoot | Out-Null
    $scan = Invoke-SensitiveScan -ProjectRoot $ProjectRoot -Allow:$AllowSensitive
    New-ReviewPackage -ProjectRoot $ProjectRoot -ScanPath $scan -ForceFullBaseline:$ForceBaseline | Out-Null
    Show-PromptHandoff -ProjectRoot $ProjectRoot -MarkSent:$Send
  }
}

$global:LASTEXITCODE = 0
