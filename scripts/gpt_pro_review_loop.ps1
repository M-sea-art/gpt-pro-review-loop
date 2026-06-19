[CmdletBinding()]
param(
  [ValidateSet("Init", "Prepare", "SendPrompt", "CaptureFeedback", "WaitFeedback", "AssessFeedback", "SendAssessment", "RecordExperience", "Status", "Run")]
  [string]$Action = "Run",
  [string]$Root,
  [string]$TargetChatGptUrl,
  [switch]$AllowSensitive,
  [switch]$Send,
  [string]$FeedbackText,
  [string]$FeedbackFile,
  [string]$AssessmentText,
  [string]$AssessmentFile,
  [string]$ExperienceOutcome = "unspecified",
  [string]$ExperienceLesson,
  [string]$ExperienceNotes
)

$ErrorActionPreference = "Stop"

$SkipDirectories = @(
  ".git", ".hg", ".svn", ".codegraph",
  "node_modules", ".venv", "venv", "__pycache__",
  "dist", "build", "target", ".next", ".cache",
  ".pytest_cache", ".mypy_cache", ".ruff_cache"
)

function Resolve-ProjectRoot {
  param([string]$Candidate)

  if ($Candidate) {
    return (Resolve-Path -LiteralPath $Candidate).Path
  }

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
    Feedback = Join-Path $base "gpt-feedback"
    Assessments = Join-Path $base "codex-assessments"
    SecurityScans = Join-Path $base "security-scans"
    ExperienceLog = Join-Path $base "experience-log.md"
    ExperienceIssues = Join-Path $base "experience-issues"
  }
}

function Test-ChatGptUrl {
  param([string]$Url)
  if (-not $Url) {
    return $false
  }
  return ($Url.Trim() -match "^https://chatgpt\.com/")
}

function ConvertTo-ChatGptTargetUrl {
  param([string]$Url)
  if (-not $Url) {
    return $null
  }
  return $Url.Trim()
}

function Get-RelativePath {
  param(
    [Parameter(Mandatory = $true)][string]$Root,
    [Parameter(Mandatory = $true)][string]$Path
  )
  return ([System.IO.Path]::GetRelativePath($Root, $Path) -replace "\\", "/")
}

function Ensure-ReviewLoop {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$ChatUrl
  )

  $paths = Get-ReviewPaths $ProjectRoot
  foreach ($dir in @($paths.Base, $paths.Dossiers, $paths.CodeMaps, $paths.RoundRequests, $paths.Prompts, $paths.Feedback, $paths.Assessments, $paths.SecurityScans, $paths.ExperienceIssues)) {
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

  $targetUrl = ConvertTo-ChatGptTargetUrl $ChatUrl
  if (Test-Path -LiteralPath $paths.Config) {
    $config = Read-JsonFile $paths.Config
    if ($targetUrl) {
      Set-ObjectProperty $config "target_chatgpt_conversation_url" $targetUrl
      Set-ObjectProperty $config "target_chatgpt_url" $targetUrl
    }
  } else {
    $config = [ordered]@{
      target_chatgpt_conversation_url = $targetUrl
      target_chatgpt_url = $targetUrl
      transport = "browser_dossier"
      run_mode = "semi_auto"
      review_memory = "chatgpt_project_conversation"
      baseline_policy = "first_round_full_then_delta"
      sensitive_scan_policy = "block_unless_allow_sensitive"
      code_map_policy = "filesystem_map_with_optional_codegraph_context"
      codex_assessment_required = $true
      feedback_return_policy = "send_local_assessment_to_same_chat"
      local_project_name = (Split-Path -Leaf $ProjectRoot)
    }
  }

  Set-ObjectProperty $config "transport" "browser_dossier"
  Set-ObjectProperty $config "run_mode" "semi_auto"
  Set-ObjectProperty $config "review_memory" "chatgpt_project_conversation"
  Set-ObjectProperty $config "baseline_policy" "first_round_full_then_delta"
  Set-ObjectProperty $config "codex_assessment_required" $true
  Set-ObjectProperty $config "feedback_return_policy" "send_local_assessment_to_same_chat"
  Set-ObjectProperty $config "local_project_name" (Split-Path -Leaf $ProjectRoot)
  ConvertTo-JsonFile $config $paths.Config

  if (-not (Test-Path -LiteralPath $paths.State)) {
    $state = [ordered]@{
      version = 2
      updated_at = (Get-Date).ToString("o")
      baseline_sent = $false
      baseline_hash = $null
      round_counter = 0
      pending_for_gpt = @()
      pending_for_codex = @()
      pending_assessments_for_gpt = @()
      latest_prompt = $null
      latest_feedback = $null
      latest_assessment = $null
      target_chatgpt_conversation_url = $targetUrl
    }
    ConvertTo-JsonFile $state $paths.State
  } else {
    $state = Read-JsonFile $paths.State
    Set-ObjectProperty $state "version" 2
    Set-ObjectProperty $state "target_chatgpt_conversation_url" $config.target_chatgpt_conversation_url
    Set-ObjectProperty $state "updated_at" (Get-Date).ToString("o")
    foreach ($field in @("pending_for_gpt", "pending_for_codex", "pending_assessments_for_gpt")) {
      if (-not ($state.PSObject.Properties.Name -contains $field) -or $null -eq $state.$field) {
        Set-ObjectProperty $state $field @()
      }
    }
    foreach ($field in @("baseline_sent", "baseline_hash", "round_counter", "latest_prompt", "latest_feedback", "latest_assessment")) {
      if (-not ($state.PSObject.Properties.Name -contains $field)) {
        $default = $null
        if ($field -eq "baseline_sent") { $default = $false }
        if ($field -eq "round_counter") { $default = 0 }
        Set-ObjectProperty $state $field $default
      }
    }
    ConvertTo-JsonFile $state $paths.State
  }

  return $paths
}

function Get-Config {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $paths = Get-ReviewPaths $ProjectRoot
  if (-not (Test-Path -LiteralPath $paths.Config)) {
    throw "Missing project config. Run -Action Init -TargetChatGptUrl <chatgpt-url> first."
  }
  return Read-JsonFile $paths.Config
}

function Get-State {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)
  $paths = Get-ReviewPaths $ProjectRoot
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
  $paths = Get-ReviewPaths $ProjectRoot
  Set-ObjectProperty $State "updated_at" (Get-Date).ToString("o")
  ConvertTo-JsonFile $State $paths.State
}

function Add-StateItem {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string]$Field,
    [Parameter(Mandatory = $true)][string]$Value
  )

  $state = Get-State -ProjectRoot $ProjectRoot
  if (-not ($state.PSObject.Properties.Name -contains $Field) -or $null -eq $state.$Field) {
    Set-ObjectProperty $state $Field @()
  }
  $items = @($state.$Field)
  if ($items -notcontains $Value) {
    Set-ObjectProperty $state $Field @($items + $Value)
  }
  Save-State $ProjectRoot $state
}

function Get-GitText {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [Parameter(Mandatory = $true)][string[]]$Args
  )

  try {
    $output = & git -C $ProjectRoot @Args 2>$null
    if ($LASTEXITCODE -eq 0) {
      return ($output -join "`n").Trim()
    }
  } catch {
  } finally {
    $global:LASTEXITCODE = 0
  }
  return ""
}

function Test-SkippedPath {
  param(
    [Parameter(Mandatory = $true)][string]$RelativePath
  )
  $parts = $RelativePath -split "[\\/]"
  foreach ($part in $parts) {
    if ($SkipDirectories -contains $part) {
      return $true
    }
  }
  return $false
}

function Get-ProjectFiles {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [int]$Limit = 500
  )

  $files = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    ForEach-Object {
      $relative = Get-RelativePath $ProjectRoot $_.FullName
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

  return $files
}

function Get-ProjectTreeText {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)

  $items = @(Get-ChildItem -LiteralPath $ProjectRoot -Force -ErrorAction SilentlyContinue |
    Where-Object { -not ($SkipDirectories -contains $_.Name) } |
    Sort-Object @{ Expression = { -not $_.PSIsContainer } }, Name |
    Select-Object -First 100)
  if ($items.Count -eq 0) {
    return "(empty project root)"
  }
  return ($items | ForEach-Object {
    if ($_.PSIsContainer) { "[dir]  " + $_.Name } else { "[file] " + $_.Name }
  }) -join "`n"
}

function Get-KeyFiles {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)

  $patterns = @(
    "AGENTS.md", "README.md", "package.json", "pnpm-lock.yaml", "yarn.lock", "package-lock.json",
    "pyproject.toml", "requirements.txt", "Cargo.toml", "go.mod", "deno.json", "tsconfig.json",
    "vite.config.*", "next.config.*", "godot.project", "project.godot", "*.sln", "*.csproj"
  )
  $found = New-Object System.Collections.Generic.List[string]
  foreach ($pattern in $patterns) {
    $matches = @(Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force -Filter $pattern -ErrorAction SilentlyContinue |
      Where-Object {
        $relative = Get-RelativePath $ProjectRoot $_.FullName
        -not (Test-SkippedPath $relative)
      } |
      Select-Object -First 20)
    foreach ($item in $matches) {
      $found.Add((Get-RelativePath $ProjectRoot $item.FullName)) | Out-Null
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
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot $candidate)) {
      $hints.Add("Detected $candidate") | Out-Null
    }
  }
  if ($hints.Count -eq 0) {
    $hints.Add("(no obvious test command discovered)") | Out-Null
  }
  return @($hints.ToArray())
}

function Get-ContentExcerpt {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [int]$MaxChars = 6000
  )

  try {
    $fileInfo = Get-Item -LiteralPath $Path -ErrorAction Stop
    if ($fileInfo.Length -gt 524288) {
      return "(skipped: file larger than 512 KiB)"
    }
    $text = Get-Content -Raw -LiteralPath $Path -ErrorAction Stop
    if ($text.Length -gt $MaxChars) {
      return $text.Substring(0, $MaxChars) + "`n...(truncated)"
    }
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
  $files = Get-ProjectFiles $ProjectRoot 20000

  foreach ($file in $files) {
    $name = Split-Path -Leaf $file.path
    foreach ($rule in $riskyNames) {
      if ($name -match $rule) {
        $issues.Add([pscustomobject]@{ path = $file.path; type = "risky_filename"; rule = $rule }) | Out-Null
        break
      }
    }

    if ($file.length -gt 1048576) {
      continue
    }

    $fullPath = Join-Path $ProjectRoot ($file.path -replace "/", "\")
    try {
      $text = Get-Content -Raw -LiteralPath $fullPath -ErrorAction Stop
    } catch {
      continue
    }

    foreach ($rule in $patterns) {
      if ($text -match $rule.pattern) {
        $issues.Add([pscustomobject]@{ path = $file.path; type = "content_pattern"; rule = $rule.name }) | Out-Null
      }
    }

    if ($issues.Count -ge 50) {
      break
    }
  }

  $result = [ordered]@{
    created_at = (Get-Date).ToString("o")
    project_name = (Split-Path -Leaf $ProjectRoot)
    transport = "browser_dossier"
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
    [Parameter(Mandatory = $true, Position = 0)][string]$ProjectRoot,
    [Parameter(Mandatory = $true, Position = 1)][string]$ScanPath,
    [Parameter(Mandatory = $true, Position = 2)][string]$RoundId
  )

  $dossierDir = [System.IO.Path]::Combine($ProjectRoot, "docs", "ai-review-loop", "dossiers")
  if (-not (Test-Path -LiteralPath $dossierDir)) {
    New-Item -ItemType Directory -Path $dossierDir -Force | Out-Null
  }
  $dossierPath = [System.IO.Path]::Combine($dossierDir, "$RoundId-project-dossier.md")
  $projectName = Split-Path -Leaf $ProjectRoot
  $branch = Get-GitText $ProjectRoot @("branch", "--show-current")
  if (-not $branch) { $branch = "(not a git repo or detached)" }
  $gitStatus = Get-GitText $ProjectRoot @("status", "--short")
  if (-not $gitStatus) { $gitStatus = "(clean, not a git repo, or unavailable)" }
  $recentCommits = Get-GitText $ProjectRoot @("log", "--oneline", "-8")
  if (-not $recentCommits) { $recentCommits = "(not available)" }
  $tree = Get-ProjectTreeText $ProjectRoot
  $keyFiles = Get-KeyFiles $ProjectRoot
  if ($keyFiles.Count -eq 0) { $keyFiles = @("(none discovered)") }
  $tests = Get-TestHints $ProjectRoot
  $scanRel = Get-RelativePath $ProjectRoot $ScanPath

  $body = @"
# Project Dossier

- id: $RoundId-dossier
- created_at: $(Get-Date -Format o)
- source: codex
- target: gpt-pro
- transport: browser_dossier
- status: baseline_material
- project_name: $projectName

## Use

This dossier is a local, sanitized project baseline for GPT Pro review. It replaces direct file access. Treat paths as project-relative. Do not assume access to local files beyond the material Codex sends in this ChatGPT conversation.

## Project Snapshot

- branch: $branch
- security_scan: $scanRel
- code_access_policy: summaries, code map, diffs, and necessary excerpts only

## Top-Level Layout

```text
$tree
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

## Reviewer Instructions

- Review the material Codex provides in this conversation.
- Ask Codex for missing snippets instead of assuming direct repository access.
- Give concrete concerns, expected tests, and recommended actions.
- Codex will locally assess each recommendation before execution and report back.
"@

  Set-Content -LiteralPath $dossierPath -Encoding UTF8 -Value $body
  return $dossierPath
}

function New-CodeMap {
  param(
    [Parameter(Mandatory = $true, Position = 0)][string]$ProjectRoot,
    [Parameter(Mandatory = $true, Position = 1)][string]$RoundId
  )

  $codeMapDir = [System.IO.Path]::Combine($ProjectRoot, "docs", "ai-review-loop", "code-maps")
  if (-not (Test-Path -LiteralPath $codeMapDir)) {
    New-Item -ItemType Directory -Path $codeMapDir -Force | Out-Null
  }
  $codeMapPath = [System.IO.Path]::Combine($codeMapDir, "$RoundId-code-map.md")
  $files = @(Get-ProjectFiles -ProjectRoot $ProjectRoot -Limit 1200)
  $byExt = @($files |
    Group-Object extension |
    Sort-Object Count -Descending |
    Select-Object -First 20 |
    ForEach-Object {
      $name = if ($_.Name) { $_.Name } else { "(no extension)" }
      "{0}: {1}" -f $name, $_.Count
    })
  if ($byExt.Count -eq 0) { $byExt = @("(no files)") }

  $important = @($files | Where-Object {
    $_.path -match "(^|/)(src|app|lib|server|client|tests?|spec|docs|scripts|tools)/" -or
    $_.path -match "(AGENTS|README|package|pyproject|Cargo|go\.mod|tsconfig|vite|next|godot|project)\."
  } | Select-Object -First 300)
  if ($important.Count -eq 0) {
    $important = @($files | Select-Object -First 120)
  }

  $fileLines = @($important | ForEach-Object {
    "- {0} ({1} bytes)" -f $_.path, $_.length
  })
  if ($fileLines.Count -eq 0) { $fileLines = @("- (no project files discovered)") }

  $diffSummary = Get-GitText -ProjectRoot $ProjectRoot -Args @("diff", "--stat")
  if (-not $diffSummary) { $diffSummary = "(no unstaged diff stat or unavailable)" }
  $stagedDiffSummary = Get-GitText -ProjectRoot $ProjectRoot -Args @("diff", "--cached", "--stat")
  if (-not $stagedDiffSummary) { $stagedDiffSummary = "(no staged diff stat or unavailable)" }

  $bodyLines = @(
    "# Code Map",
    "",
    "- id: $RoundId-code-map",
    "- created_at: $(Get-Date -Format o)",
    "- source: codex",
    "- target: gpt-pro",
    "- transport: browser_dossier",
    "- status: code_map",
    "",
    "## CodeGraph Note",
    "",
    "If Codex has CodeGraph available in the active project, Codex should add structural summaries from CodeGraph to the review prompt. This script provides a deterministic filesystem fallback and does not require CodeGraph.",
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
    '```',
    "",
    "## Staged Diff Stat",
    "",
    '```text',
    $stagedDiffSummary,
    '```'
  )

  Set-Content -LiteralPath $codeMapPath -Encoding UTF8 -Value ($bodyLines -join [Environment]::NewLine)
  return $codeMapPath
}

function New-RoundRequest {
  param(
    [Parameter(Mandatory = $true, Position = 0)][string]$ProjectRoot,
    [Parameter(Mandatory = $true, Position = 1)][string]$RoundId,
    [Parameter(Mandatory = $true, Position = 2)][string]$ScanPath
  )

  if ([string]::IsNullOrWhiteSpace($ProjectRoot)) {
    throw "New-RoundRequest received an empty ProjectRoot."
  }
  $requestDir = [System.IO.Path]::Combine($ProjectRoot, "docs", "ai-review-loop", "round-requests")
  if (-not (Test-Path -LiteralPath $requestDir)) {
    New-Item -ItemType Directory -Path $requestDir -Force | Out-Null
  }
  $requestPath = [System.IO.Path]::Combine($requestDir, "$RoundId-round-request.md")
  $gitStatus = Get-GitText -ProjectRoot $ProjectRoot -Args @("status", "--short")
  if (-not $gitStatus) { $gitStatus = "(clean, not a git repo, or unavailable)" }
  $diffStat = Get-GitText -ProjectRoot $ProjectRoot -Args @("diff", "--stat")
  if (-not $diffStat) { $diffStat = "(no unstaged diff stat or unavailable)" }
  $cachedDiffStat = Get-GitText -ProjectRoot $ProjectRoot -Args @("diff", "--cached", "--stat")
  if (-not $cachedDiffStat) { $cachedDiffStat = "(no staged diff stat or unavailable)" }
  $scanRel = Get-RelativePath -Root $ProjectRoot -Path $ScanPath

  $bodyLines = @(
    "# GPT Pro Review Request",
    "",
    "- id: $RoundId-request",
    "- created_at: $(Get-Date -Format o)",
    "- source: codex",
    "- target: gpt-pro",
    "- transport: browser_dossier",
    "- status: ready_for_review",
    "- security_scan: $scanRel",
    "",
    "## Requested Review",
    "",
    "Review this round using the baseline already present in this ChatGPT conversation plus the material below. Focus on correctness, risks, missing tests, privacy/security concerns, and whether Codex should proceed.",
    "",
    "## Local Changes Since Last Review",
    "",
    '```text',
    $gitStatus,
    '```',
    "",
    "## Unstaged Diff Stat",
    "",
    '```text',
    $diffStat,
    '```',
    "",
    "## Staged Diff Stat",
    "",
    '```text',
    $cachedDiffStat,
    '```',
    "",
    "## Feedback Format",
    "",
    "Return:",
    "",
    "1. Verdict: APPROVE, NEEDS_CHANGES, BLOCKED, or NEEDS_MORE_CONTEXT.",
    "2. Findings ordered by severity.",
    "3. Recommended Codex actions.",
    "4. Tests or verification expected from Codex.",
    "5. Anything to reject or defer.",
    "",
    "Codex will locally assess each recommendation before acting and will send you a practice-based response."
  )

  Set-Content -LiteralPath $requestPath -Encoding UTF8 -Value ($bodyLines -join [Environment]::NewLine)
  return $requestPath
}

function Get-FileHashText {
  param([string[]]$Paths)

  $sha = [System.Security.Cryptography.SHA256]::Create()
  $builder = New-Object System.Text.StringBuilder
  foreach ($path in $Paths) {
    if (Test-Path -LiteralPath $path) {
      [void]$builder.AppendLine((Get-Content -Raw -LiteralPath $path))
    }
  }
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($builder.ToString())
  return [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").ToLowerInvariant()
}

function New-ReviewPrompt {
  param(
    [Parameter(Mandatory = $true, Position = 0)][string]$ProjectRoot,
    [Parameter(Mandatory = $true, Position = 1)][string]$RoundId,
    [Parameter(Mandatory = $true, Position = 2)][string]$DossierPath,
    [Parameter(Mandatory = $true, Position = 3)][string]$CodeMapPath,
    [Parameter(Mandatory = $true, Position = 4)][string]$RequestPath
  )

  $paths = Get-ReviewPaths $ProjectRoot
  $state = Get-State $ProjectRoot
  $promptPath = Join-Path $paths.Prompts "$RoundId-review-prompt.md"
  $includeBaseline = -not [bool]$state.baseline_sent

  $dossier = if ($includeBaseline) { Get-ContentExcerpt $DossierPath 18000 } else { "(baseline already sent in this ChatGPT conversation; ask Codex if you need it repeated)" }
  $codeMap = if ($includeBaseline) { Get-ContentExcerpt $CodeMapPath 22000 } else { "(baseline code map already sent; this round is delta-only)" }
  $request = Get-ContentExcerpt $RequestPath 18000

  $prompt = @"
You are GPT Pro reviewing a Codex project through an offline review loop.

Use only the project baseline and round material in this ChatGPT conversation. You do not have direct local file access. If you need more context, ask Codex for a specific snippet or command result.

Codex must locally assess your recommendations before acting and will report back with accept/modify/reject/needs-more-info decisions based on real project constraints.

## Round

$RoundId

## Baseline Dossier

$dossier

## Code Map

$codeMap

## Round Request

$request
"@

  Set-Content -LiteralPath $promptPath -Encoding UTF8 -Value $prompt
  Set-ObjectProperty $state "latest_prompt" (Get-RelativePath $ProjectRoot $promptPath)
  Add-StateItem $ProjectRoot "pending_for_gpt" (Get-RelativePath $ProjectRoot $promptPath)
  return $promptPath
}

function New-ReviewPackage {
  param(
    [Parameter(Mandatory = $true, Position = 0)][string]$ProjectRoot,
    [Parameter(Mandatory = $true, Position = 1)][string]$ScanPath
  )

  $state = Get-State $ProjectRoot
  $roundNumber = [int]$state.round_counter + 1
  $roundId = "round-{0:000}-{1}" -f $roundNumber, (Get-Date -Format "yyyyMMdd-HHmmss")

  $dossierPath = New-ProjectDossier -ProjectRoot $ProjectRoot -ScanPath $ScanPath -RoundId $roundId
  $codeMapPath = New-CodeMap -ProjectRoot $ProjectRoot -RoundId $roundId
  $requestPath = New-RoundRequest -ProjectRoot $ProjectRoot -RoundId $roundId -ScanPath $ScanPath
  $promptPath = New-ReviewPrompt -ProjectRoot $ProjectRoot -RoundId $roundId -DossierPath $dossierPath -CodeMapPath $codeMapPath -RequestPath $requestPath
  $baselineHash = Get-FileHashText @($dossierPath, $codeMapPath)

  $state = Get-State -ProjectRoot $ProjectRoot
  Set-ObjectProperty -Object $state -Name "round_counter" -Value $roundNumber
  Set-ObjectProperty -Object $state -Name "baseline_hash" -Value $baselineHash
  Set-ObjectProperty -Object $state -Name "latest_dossier" -Value (Get-RelativePath -Root $ProjectRoot -Path $dossierPath)
  Set-ObjectProperty -Object $state -Name "latest_code_map" -Value (Get-RelativePath -Root $ProjectRoot -Path $codeMapPath)
  Set-ObjectProperty -Object $state -Name "latest_round_request" -Value (Get-RelativePath -Root $ProjectRoot -Path $requestPath)
  Set-ObjectProperty -Object $state -Name "latest_prompt" -Value (Get-RelativePath -Root $ProjectRoot -Path $promptPath)
  Save-State -ProjectRoot $ProjectRoot -State $state

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
    [Parameter(Mandatory = $true)][string]$PromptPath
  )

  $state = Get-State $ProjectRoot
  Set-ObjectProperty $state "baseline_sent" $true
  Set-ObjectProperty $state "latest_prompt" (Get-RelativePath $ProjectRoot $PromptPath)
  Set-ObjectProperty $state "latest_prompt_sent_at" (Get-Date).ToString("o")
  Save-State $ProjectRoot $state
}

function Show-PromptHandoff {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [switch]$MarkSent
  )

  $paths = Get-ReviewPaths $ProjectRoot
  $config = Get-Config $ProjectRoot
  $state = Get-State $ProjectRoot
  $promptRel = $state.latest_prompt
  if (-not $promptRel) {
    throw "No prompt is prepared. Run -Action Prepare first."
  }
  $promptPath = Join-Path $ProjectRoot ($promptRel -replace "/", "\")
  if (-not (Test-Path -LiteralPath $promptPath)) {
    throw "Prepared prompt does not exist: $promptPath"
  }
  $target = $config.target_chatgpt_conversation_url
  if (-not $target) { $target = $config.target_chatgpt_url }
  if (-not (Test-ChatGptUrl $target)) {
    throw "project-config.json needs target_chatgpt_conversation_url set to a https://chatgpt.com/... URL."
  }

  Write-Host "Open this ChatGPT target with the edge-browser-control skill:" -ForegroundColor Cyan
  Write-Host $target
  Write-Host "Paste or send this prompt file:" -ForegroundColor Cyan
  Write-Host $promptPath
  Write-Host "Offline browser dossier only. No local service or public endpoint is used." -ForegroundColor Green

  if ($MarkSent) {
    Complete-PromptSend $ProjectRoot $promptPath
    Write-Host "Marked prompt as sent. Baseline is now recorded as sent for delta-only future rounds." -ForegroundColor Green
  } else {
    Write-Host "After Edge successfully submits it, rerun SendPrompt with -Send to mark it as sent." -ForegroundColor Yellow
  }
}

function Get-LatestFile {
  param(
    [Parameter(Mandatory = $true)][string]$Directory,
    [string]$Filter = "*.md"
  )
  if (-not (Test-Path -LiteralPath $Directory)) {
    return $null
  }
  return Get-ChildItem -LiteralPath $Directory -File -Filter $Filter -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Save-GptFeedback {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$Text,
    [string]$File
  )

  $paths = Get-ReviewPaths $ProjectRoot
  if ($File) {
    $feedbackText = Get-Content -Raw -LiteralPath $File
  } elseif ($Text) {
    $feedbackText = $Text
  } else {
    throw "CaptureFeedback requires -FeedbackText or -FeedbackFile."
  }

  $state = Get-State $ProjectRoot
  $round = if ($state.round_counter) { "round-{0:000}" -f [int]$state.round_counter } else { "round-000" }
  $feedbackPath = Join-Path $paths.Feedback ("{0}-{1}-gpt-feedback.md" -f $round, (Get-Date -Format "yyyyMMdd-HHmmss"))
  $relatedPrompt = if ($state.latest_prompt) { $state.latest_prompt } else { "(unknown)" }

  $body = @"
# GPT Pro Feedback

- id: $round-gpt-feedback
- created_at: $(Get-Date -Format o)
- source: gpt-pro
- target: codex
- transport: browser_dossier
- status: ready_for_codex_local_assessment
- related_prompt: $relatedPrompt

## Feedback

$feedbackText
"@

  Set-Content -LiteralPath $feedbackPath -Encoding UTF8 -Value $body
  $feedbackRel = Get-RelativePath $ProjectRoot $feedbackPath
  Add-StateItem $ProjectRoot "pending_for_codex" $feedbackRel
  $state = Get-State $ProjectRoot
  Set-ObjectProperty $state "latest_feedback" $feedbackRel
  Save-State $ProjectRoot $state
  Write-Host "GPT feedback saved: $feedbackPath" -ForegroundColor Green
  return $feedbackPath
}

function New-LocalAssessment {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$Text,
    [string]$File
  )

  $paths = Get-ReviewPaths $ProjectRoot
  $state = Get-State $ProjectRoot
  $latestFeedback = if ($state.latest_feedback) { Join-Path $ProjectRoot ($state.latest_feedback -replace "/", "\") } else { $null }
  if (-not $latestFeedback -or -not (Test-Path -LiteralPath $latestFeedback)) {
    $candidate = Get-LatestFile $paths.Feedback
    if ($candidate) { $latestFeedback = $candidate.FullName }
  }
  if (-not $latestFeedback -or -not (Test-Path -LiteralPath $latestFeedback)) {
    throw "No GPT feedback found. Run -Action CaptureFeedback first."
  }

  if ($File) {
    $assessmentText = Get-Content -Raw -LiteralPath $File
  } elseif ($Text) {
    $assessmentText = $Text
  } else {
    $feedbackExcerpt = Get-ContentExcerpt $latestFeedback 12000
    $gitStatus = Get-GitText $ProjectRoot @("status", "--short")
    if (-not $gitStatus) { $gitStatus = "(clean, not a git repo, or unavailable)" }
    $assessmentText = @"
## Codex Local Judgment Required

Codex must replace this draft with local practice-based judgments before implementation. Classify each GPT recommendation as `accept`, `modify`, `reject`, or `needs-more-info`.

## Local Evidence Snapshot

```text
$gitStatus
```

## GPT Feedback To Assess

$feedbackExcerpt

## Assessment Table

| GPT recommendation | Codex decision | Local evidence | Action |
|---|---|---|---|
| (fill from GPT feedback) | needs-more-info | (cite local code/test/constraint) | (ask GPT or user) |
"@
  }

  $round = if ($state.round_counter) { "round-{0:000}" -f [int]$state.round_counter } else { "round-000" }
  $assessmentPath = Join-Path $paths.Assessments ("{0}-{1}-codex-local-assessment.md" -f $round, (Get-Date -Format "yyyyMMdd-HHmmss"))
  $feedbackRel = Get-RelativePath $ProjectRoot $latestFeedback

  $body = @"
# Codex Local Assessment

- id: $round-codex-local-assessment
- created_at: $(Get-Date -Format o)
- source: codex
- target: gpt-pro
- transport: browser_dossier
- status: ready_to_return_to_gpt
- related_feedback: $feedbackRel

$assessmentText
"@

  Set-Content -LiteralPath $assessmentPath -Encoding UTF8 -Value $body
  $assessmentRel = Get-RelativePath $ProjectRoot $assessmentPath
  Add-StateItem $ProjectRoot "pending_assessments_for_gpt" $assessmentRel
  $state = Get-State $ProjectRoot
  Set-ObjectProperty $state "latest_assessment" $assessmentRel
  Save-State $ProjectRoot $state
  Write-Host "Codex local assessment saved: $assessmentPath" -ForegroundColor Green
  return $assessmentPath
}

function New-AssessmentPrompt {
  param([Parameter(Mandatory = $true)][string]$ProjectRoot)

  $paths = Get-ReviewPaths $ProjectRoot
  $config = Get-Config $ProjectRoot
  $state = Get-State $ProjectRoot
  $assessmentRel = $state.latest_assessment
  if (-not $assessmentRel) {
    throw "No local assessment found. Run -Action AssessFeedback first."
  }
  $assessmentPath = Join-Path $ProjectRoot ($assessmentRel -replace "/", "\")
  if (-not (Test-Path -LiteralPath $assessmentPath)) {
    throw "Assessment file does not exist: $assessmentPath"
  }

  $target = $config.target_chatgpt_conversation_url
  if (-not $target) { $target = $config.target_chatgpt_url }
  if (-not (Test-ChatGptUrl $target)) {
    throw "project-config.json needs target_chatgpt_conversation_url set to a https://chatgpt.com/... URL."
  }

  $round = if ($state.round_counter) { "round-{0:000}" -f [int]$state.round_counter } else { "round-000" }
  $promptPath = Join-Path $paths.Prompts ("{0}-{1}-codex-assessment-return-prompt.md" -f $round, (Get-Date -Format "yyyyMMdd-HHmmss"))
  $assessment = Get-ContentExcerpt $assessmentPath 22000
  $prompt = @"
Codex has locally assessed your GPT Pro feedback against the real project state.

Please review this practice-based response, correct any recommendation that no longer fits, and identify the next narrow review question if another round is useful.

## Codex Local Assessment

$assessment
"@

  Set-Content -LiteralPath $promptPath -Encoding UTF8 -Value $prompt
  Set-ObjectProperty $state "latest_assessment_prompt" (Get-RelativePath $ProjectRoot $promptPath)
  Save-State $ProjectRoot $state

  Write-Host "Open this ChatGPT target with the edge-browser-control skill:" -ForegroundColor Cyan
  Write-Host $target
  Write-Host "Send this assessment-return prompt:" -ForegroundColor Cyan
  Write-Host $promptPath
  if ($Send) {
    Set-ObjectProperty $state "latest_assessment_sent_at" (Get-Date).ToString("o")
    Save-State $ProjectRoot $state
    Write-Host "Marked local assessment as sent to GPT." -ForegroundColor Green
  } else {
    Write-Host "After Edge successfully submits it, rerun SendAssessment with -Send to mark it as sent." -ForegroundColor Yellow
  }
}

function New-ExperienceRecord {
  param(
    [Parameter(Mandatory = $true)][string]$ProjectRoot,
    [string]$Outcome,
    [string]$Lesson,
    [string]$Notes
  )

  Ensure-ReviewLoop $ProjectRoot $null | Out-Null
  $paths = Get-ReviewPaths $ProjectRoot
  $state = Get-State $ProjectRoot
  $stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
  $safeOutcome = if ($Outcome) { $Outcome } else { "unspecified" }
  $safeLesson = if ($Lesson) { $Lesson } else { "(fill in the reusable lesson)" }
  $safeNotes = if ($Notes) { $Notes } else { "(fill in what happened, without secrets or private data)" }
  $latestPrompt = if ($state.latest_prompt) { $state.latest_prompt } else { "(none)" }
  $latestFeedback = if ($state.latest_feedback) { $state.latest_feedback } else { "(none)" }
  $latestAssessment = if ($state.latest_assessment) { $state.latest_assessment } else { "(none)" }

  $entry = @(
    "",
    "## $stamp",
    "",
    "- outcome: $safeOutcome",
    "- latest_prompt: $latestPrompt",
    "- latest_feedback: $latestFeedback",
    "- latest_assessment: $latestAssessment",
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
  $issue = @"
# [experience] browser dossier review loop - $safeOutcome

## Scenario

Project-local use of `gpt-pro-review-loop` v2 browser dossier transport.

## Observed behavior

$safeNotes

## Reusable lesson

$safeLesson

## Local evidence

- Latest prompt: $latestPrompt
- Latest GPT feedback: $latestFeedback
- Latest Codex assessment: $latestAssessment

## Privacy check

This draft should contain only process-level experience. Do not paste API keys, cookies, private account data, proprietary source snippets, or private business data into the public GitHub issue.
"@
  Set-Content -LiteralPath $issuePath -Encoding UTF8 -Value $issue

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
    config_path = $paths.Config
    state_path = $paths.State
    transport = if ($config) { $config.transport } else { $null }
    target_chatgpt_conversation_url = if ($config) { $config.target_chatgpt_conversation_url } else { $null }
    baseline_sent = if ($state) { $state.baseline_sent } else { $false }
    round_counter = if ($state) { $state.round_counter } else { 0 }
    latest_prompt = if ($state) { $state.latest_prompt } else { $null }
    latest_feedback = if ($state) { $state.latest_feedback } else { $null }
    latest_assessment = if ($state) { $state.latest_assessment } else { $null }
  } | Format-List
}

$ProjectRoot = Resolve-ProjectRoot $Root

switch ($Action) {
  "Init" {
    Ensure-ReviewLoop $ProjectRoot $TargetChatGptUrl | Out-Null
    Write-Host "GPT Pro review loop v2 initialized for project: $(Split-Path -Leaf $ProjectRoot)" -ForegroundColor Green
  }
  "Prepare" {
    Ensure-ReviewLoop $ProjectRoot $TargetChatGptUrl | Out-Null
    $scan = Invoke-SensitiveScan $ProjectRoot -Allow:$AllowSensitive
    New-ReviewPackage $ProjectRoot $scan | Out-Null
  }
  "SendPrompt" {
    Ensure-ReviewLoop $ProjectRoot $TargetChatGptUrl | Out-Null
    Show-PromptHandoff $ProjectRoot -MarkSent:$Send
  }
  "CaptureFeedback" {
    Ensure-ReviewLoop $ProjectRoot $TargetChatGptUrl | Out-Null
    Save-GptFeedback $ProjectRoot $FeedbackText $FeedbackFile | Out-Null
  }
  "WaitFeedback" {
    Ensure-ReviewLoop $ProjectRoot $TargetChatGptUrl | Out-Null
    $paths = Get-ReviewPaths $ProjectRoot
    $latest = Get-LatestFile $paths.Feedback
    if (-not $latest) {
      throw "No GPT feedback has been captured yet. Use -Action CaptureFeedback after reading the ChatGPT reply through Edge."
    }
    Write-Host "Latest captured GPT feedback: $($latest.FullName)" -ForegroundColor Green
  }
  "AssessFeedback" {
    Ensure-ReviewLoop $ProjectRoot $TargetChatGptUrl | Out-Null
    New-LocalAssessment $ProjectRoot $AssessmentText $AssessmentFile | Out-Null
  }
  "SendAssessment" {
    Ensure-ReviewLoop $ProjectRoot $TargetChatGptUrl | Out-Null
    New-AssessmentPrompt $ProjectRoot
  }
  "RecordExperience" {
    New-ExperienceRecord $ProjectRoot $ExperienceOutcome $ExperienceLesson $ExperienceNotes
  }
  "Status" {
    Show-Status $ProjectRoot
  }
  "Run" {
    Ensure-ReviewLoop $ProjectRoot $TargetChatGptUrl | Out-Null
    $scan = Invoke-SensitiveScan $ProjectRoot -Allow:$AllowSensitive
    New-ReviewPackage $ProjectRoot $scan | Out-Null
    Show-PromptHandoff $ProjectRoot -MarkSent:$Send
  }
}

$global:LASTEXITCODE = 0
