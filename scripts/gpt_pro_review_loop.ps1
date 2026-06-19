[CmdletBinding()]
param(
  [ValidateSet("Init", "Prepare", "StartSession", "PreflightConnector", "SendPrompt", "WaitFeedback", "RecordExperience", "StopSession", "Status", "Run")]
  [string]$Action = "Run",
  [string]$Root,
  [string]$TargetChatGptUrl,
  [int]$Port = 7676,
  [switch]$AllowSensitive,
  [switch]$Send,
  [int]$FeedbackTimeoutSeconds = 900,
  [int]$ConnectorTimeoutSeconds = 300,
  [int]$StartupTimeoutSeconds = 90,
  [int]$TunnelTimeoutSeconds = 90,
  [string]$ExperienceOutcome = "unspecified",
  [string]$ExperienceLesson,
  [string]$ExperienceNotes,
  [switch]$StopDevSpace
)

$ErrorActionPreference = "Stop"

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
  }

  return (Resolve-Path -LiteralPath (Get-Location).Path).Path
}

function Get-ProjectId {
  param([string]$ProjectRoot)

  $sha = [System.Security.Cryptography.SHA256]::Create()
  $bytes = [System.Text.Encoding]::UTF8.GetBytes($ProjectRoot.ToLowerInvariant())
  $hash = [System.BitConverter]::ToString($sha.ComputeHash($bytes)).Replace("-", "").Substring(0, 12).ToLowerInvariant()
  $name = Split-Path -Leaf $ProjectRoot
  $safeName = ($name -replace "[^A-Za-z0-9_.-]", "_")
  return "$safeName-$hash"
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
  param([string]$Path)
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

function Test-ChatGptConversationUrl {
  param([string]$Url)

  if (-not $Url) {
    return $false
  }
  return ($Url.Trim() -match "^https://chatgpt\.com/(?:.+/)?c/[0-9A-Fa-f-]+")
}

function ConvertTo-ChatGptProjectUrl {
  param([string]$Url)

  if (-not $Url) {
    return $null
  }

  $trimmed = $Url.Trim()
  if ($trimmed -match "^(https://chatgpt\.com/.+?)/c/[0-9A-Fa-f-]+(?:[/?#].*)?$") {
    return $matches[1].TrimEnd("/")
  }

  return $trimmed
}

function Get-BridgePaths {
  param([string]$ProjectRoot)

  $bridge = Join-Path $ProjectRoot "docs\ai-bridge"
  return [pscustomobject]@{
    Bridge = $bridge
    Config = Join-Path $bridge "project-config.json"
    State = Join-Path $bridge "bridge-state.json"
    Decisions = Join-Path $bridge "decisions.md"
    Inbox = Join-Path $bridge "inbox"
    Reports = Join-Path $bridge "codex-reports"
    Feedback = Join-Path $bridge "gpt-pro-feedback"
    Scans = Join-Path $bridge "security-scans"
    ExperienceLog = Join-Path $bridge "experience-log.md"
    ExperienceIssues = Join-Path $bridge "experience-issues"
  }
}

function Get-RuntimePaths {
  param([string]$ProjectRoot)

  $base = Join-Path $env:LOCALAPPDATA ("gpt-pro-review-loop\" + (Get-ProjectId $ProjectRoot))
  return [pscustomobject]@{
    Base = $base
    Logs = Join-Path $base "logs"
    Session = Join-Path $base "session.json"
    Baseline = Join-Path $base "baseline-files.json"
    OwnerToken = Join-Path $base "owner-token.txt"
    DevspaceConfig = Join-Path $base "devspace-config"
    DevspaceState = Join-Path $base "devspace-state"
    Worktrees = Join-Path $base "worktrees"
  }
}

function Ensure-Bridge {
  param(
    [string]$ProjectRoot,
    [string]$ChatUrl
  )

  $paths = Get-BridgePaths $ProjectRoot
  foreach ($dir in @($paths.Bridge, $paths.Inbox, $paths.Reports, $paths.Feedback, $paths.Scans, $paths.ExperienceIssues)) {
    if (-not (Test-Path -LiteralPath $dir)) {
      New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
  }

  if (-not (Test-Path -LiteralPath $paths.Decisions)) {
    Set-Content -LiteralPath $paths.Decisions -Encoding UTF8 -Value "# AI Bridge Decisions`n"
  }

  if (-not (Test-Path -LiteralPath $paths.ExperienceLog)) {
    Set-Content -LiteralPath $paths.ExperienceLog -Encoding UTF8 -Value "# GPT Pro Review Loop Experience Log`n"
  }

  if (Test-Path -LiteralPath $paths.Config) {
    $config = Read-JsonFile $paths.Config
    if ($ChatUrl) {
      $projectUrl = ConvertTo-ChatGptProjectUrl $ChatUrl
      Set-ObjectProperty $config "target_chatgpt_project_url" $projectUrl
      Set-ObjectProperty $config "target_chatgpt_url" $projectUrl
      if ($projectUrl -ne $ChatUrl.Trim()) {
        Set-ObjectProperty $config "legacy_target_chatgpt_url" $ChatUrl.Trim()
      }
    } elseif (-not $config.target_chatgpt_project_url -and $config.target_chatgpt_url) {
      $legacyUrl = $config.target_chatgpt_url
      $projectUrl = ConvertTo-ChatGptProjectUrl $legacyUrl
      Set-ObjectProperty $config "target_chatgpt_project_url" $projectUrl
      Set-ObjectProperty $config "target_chatgpt_url" $projectUrl
      if ($projectUrl -ne $legacyUrl) {
        Set-ObjectProperty $config "legacy_target_chatgpt_url" $legacyUrl
      }
    }
  } else {
    $projectUrl = ConvertTo-ChatGptProjectUrl $ChatUrl
    $config = [ordered]@{
      target_chatgpt_project_url = $projectUrl
      target_chatgpt_url = $projectUrl
      legacy_target_chatgpt_url = if ($ChatUrl -and $projectUrl -ne $ChatUrl.Trim()) { $ChatUrl.Trim() } else { $null }
      allowed_root = $ProjectRoot
      run_mode = "semi_auto"
      review_scope = "whole_project"
      gpt_write_policy = "feedback_only"
      tunnel_policy = "quick_tunnel_per_session"
      conversation_policy = "new_chat_per_review_round"
      connector_preflight_required = $true
    }
  }
  Set-ObjectProperty $config "allowed_root" $ProjectRoot
  Set-ObjectProperty $config "conversation_policy" "new_chat_per_review_round"
  Set-ObjectProperty $config "connector_preflight_required" $true
  ConvertTo-JsonFile $config $paths.Config

  if (-not (Test-Path -LiteralPath $paths.State)) {
    $state = [ordered]@{
      version = 1
      updated_at = (Get-Date).ToString("o")
      pending_for_gpt = @()
      pending_for_codex = @()
      active_session = $null
    }
    ConvertTo-JsonFile $state $paths.State
  }

  return $paths
}

function Get-Config {
  param([string]$ProjectRoot)

  $paths = Get-BridgePaths $ProjectRoot
  if (-not (Test-Path -LiteralPath $paths.Config)) {
    throw "Missing project config. Run -Action Init -TargetChatGptUrl <chatgpt-project-url> first."
  }
  return Read-JsonFile $paths.Config
}

function Add-StateItem {
  param(
    [string]$ProjectRoot,
    [string]$Field,
    [string]$Value
  )

  $paths = Get-BridgePaths $ProjectRoot
  $state = Read-JsonFile $paths.State
  if ($null -eq $state.$Field) {
    $state | Add-Member -NotePropertyName $Field -NotePropertyValue @()
  }
  $items = @($state.$Field)
  if ($items -notcontains $Value) {
    $state.$Field = @($items + $Value)
  }
  $state.updated_at = (Get-Date).ToString("o")
  ConvertTo-JsonFile $state $paths.State
}

function Set-ActiveSession {
  param(
    [string]$ProjectRoot,
    $Session
  )

  $paths = Get-BridgePaths $ProjectRoot
  $state = Read-JsonFile $paths.State
  $state.active_session = $Session
  $state.updated_at = (Get-Date).ToString("o")
  ConvertTo-JsonFile $state $paths.State
}

function Get-RunningSession {
  param([string]$ProjectRoot)

  $runtime = Get-RuntimePaths $ProjectRoot
  if (-not (Test-Path -LiteralPath $runtime.Session)) {
    throw "No active session file found. Run -Action StartSession first."
  }
  $session = Read-JsonFile $runtime.Session
  if ($session.PSObject.Properties.Name -contains "stopped_at" -and $session.stopped_at) {
    throw "Review session is stopped. Run -Action StartSession or -Action PreflightConnector to create a fresh tunnel."
  }
  return $session
}

function Save-Session {
  param(
    [string]$ProjectRoot,
    $Session
  )

  $runtime = Get-RuntimePaths $ProjectRoot
  ConvertTo-JsonFile $Session $runtime.Session
  Set-ActiveSession $ProjectRoot $Session
}

function Set-ConnectorPreflight {
  param(
    [string]$ProjectRoot,
    $Session,
    [string]$Status,
    [string]$Reason,
    $Details
  )

  $payload = [ordered]@{
    status = $Status
    reason = $Reason
    checked_at = (Get-Date).ToString("o")
  }
  if ($Details) {
    foreach ($property in $Details.PSObject.Properties) {
      $payload[$property.Name] = $property.Value
    }
  }
  Set-ObjectProperty $Session "connector_preflight" $payload
  Save-Session $ProjectRoot $Session
}

function Get-DevSpaceHttpRequests {
  param(
    [string]$LogPath,
    [datetime]$Since
  )

  if (-not (Test-Path -LiteralPath $LogPath)) {
    return @()
  }

  $sinceUtc = $Since.ToUniversalTime()
  $requests = New-Object System.Collections.Generic.List[object]
  foreach ($line in Get-Content -LiteralPath $LogPath -ErrorAction SilentlyContinue) {
    $trimmed = $line.Trim()
    if (-not $trimmed.StartsWith("{")) {
      continue
    }
    try {
      $entry = $trimmed | ConvertFrom-Json
    } catch {
      continue
    }
    if ($entry.event -ne "http_request" -or -not $entry.ts) {
      continue
    }
    try {
      $ts = ([datetime]::Parse($entry.ts)).ToUniversalTime()
    } catch {
      continue
    }
    if ($ts -lt $sinceUtc) {
      continue
    }
    $requests.Add([pscustomobject]@{
      ts = $entry.ts
      method = $entry.method
      path = $entry.path
      status = $entry.status
      host = $entry.host
      userAgent = $entry.userAgent
      requestId = $entry.requestId
    }) | Out-Null
  }
  return @($requests.ToArray())
}

function Test-ConnectorCandidateRequest {
  param($Request)

  if (-not $Request) {
    return $false
  }
  if ($Request.path -eq "/healthz") {
    return $false
  }
  if ($Request.userAgent -and $Request.userAgent -match "PowerShell|Invoke-WebRequest") {
    return $false
  }
  return $true
}

function Test-OAuthFailureRequest {
  param($Request)

  if (-not (Test-ConnectorCandidateRequest $Request)) {
    return $false
  }
  $path = [string]$Request.path
  $status = [int]$Request.status
  $isOAuthPath = $path -match "^/(authorize|token|register|revoke|\.well-known/)"
  return ($isOAuthPath -and $status -ge 400)
}

function Format-ObservedRequest {
  param($Request)

  if (-not $Request) {
    return $null
  }
  return [ordered]@{
    ts = $Request.ts
    method = $Request.method
    path = $Request.path
    status = $Request.status
    host = $Request.host
    userAgent = $Request.userAgent
    requestId = $Request.requestId
  }
}

function Invoke-OAuthDiscoveryCheck {
  param(
    [string]$TunnelUrl,
    [string]$McpUrl,
    [int]$TimeoutSeconds = 20
  )

  $resourceUrl = "$TunnelUrl/.well-known/oauth-protected-resource/mcp"
  $authUrl = "$TunnelUrl/.well-known/oauth-authorization-server"
  $result = [ordered]@{
    resource_metadata_url = $resourceUrl
    authorization_server_metadata_url = $authUrl
    checked_at = (Get-Date).ToString("o")
    ok = $false
  }

  try {
    $resourceResponse = Invoke-WebRequest -Uri $resourceUrl -Method Get -TimeoutSec $TimeoutSeconds -SkipHttpErrorCheck
    $authResponse = Invoke-WebRequest -Uri $authUrl -Method Get -TimeoutSec $TimeoutSeconds -SkipHttpErrorCheck
    $result.resource_status = [int]$resourceResponse.StatusCode
    $result.authorization_server_status = [int]$authResponse.StatusCode

    if ([int]$resourceResponse.StatusCode -ne 200) {
      $result.error = "OAuth protected resource metadata returned HTTP $([int]$resourceResponse.StatusCode)."
      return [pscustomobject]$result
    }
    if ([int]$authResponse.StatusCode -ne 200) {
      $result.error = "OAuth authorization server metadata returned HTTP $([int]$authResponse.StatusCode)."
      return [pscustomobject]$result
    }

    $resourceMetadata = $resourceResponse.Content | ConvertFrom-Json
    $authMetadata = $authResponse.Content | ConvertFrom-Json
    $result.resource = $resourceMetadata.resource
    $result.authorization_servers = @($resourceMetadata.authorization_servers)
    $result.issuer = $authMetadata.issuer
    $result.authorization_endpoint = $authMetadata.authorization_endpoint
    $result.token_endpoint = $authMetadata.token_endpoint
    $result.registration_endpoint = $authMetadata.registration_endpoint
    $result.scopes_supported = @($authMetadata.scopes_supported)

    if ($resourceMetadata.resource -ne $McpUrl) {
      $result.error = "OAuth resource metadata does not match the current MCP URL."
      return [pscustomobject]$result
    }
    if (-not $authMetadata.authorization_endpoint -or -not $authMetadata.token_endpoint -or -not $authMetadata.registration_endpoint) {
      $result.error = "OAuth authorization metadata is missing required endpoints."
      return [pscustomobject]$result
    }
    if (@($resourceMetadata.authorization_servers) -notcontains $authMetadata.issuer) {
      $result.error = "OAuth resource metadata does not list the authorization server issuer."
      return [pscustomobject]$result
    }

    $result.ok = $true
    return [pscustomobject]$result
  } catch {
    $result.error = $_.Exception.Message
    return [pscustomobject]$result
  }
}

function Invoke-SensitiveScan {
  param(
    [string]$ProjectRoot,
    [switch]$Allow
  )

  $paths = Get-BridgePaths $ProjectRoot
  $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
  $scanPath = Join-Path $paths.Scans "$stamp-sensitive-scan.json"
  $skipDirs = @(".git", "node_modules", ".venv", "venv", "__pycache__", "dist", "build", "target", ".next", ".cache", ".codegraph")
  $riskyNames = @("^\.env($|\.)", "\.pem$", "\.key$", "id_rsa$", "id_dsa$", "cookies?\.txt$", "auth\.json$")
  $patterns = @(
    @{ name = "OpenAI-style API key"; pattern = "sk-[A-Za-z0-9_-]{20,}" },
    @{ name = "Private key header"; pattern = "-----BEGIN [A-Z ]*PRIVATE KEY-----" },
    @{ name = "Token/password assignment"; pattern = "(?i)(api[_-]?key|access[_-]?token|refresh[_-]?token|session[_-]?token|cookie|password)\s*[:=]\s*['""]?[^'""\s]{12,}" }
  )
  $issues = New-Object System.Collections.Generic.List[object]

  $files = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object {
      $relative = [System.IO.Path]::GetRelativePath($ProjectRoot, $_.FullName)
      $parts = $relative -split "[\\/]"
      -not ($parts | Where-Object { $skipDirs -contains $_ })
    }

  foreach ($file in $files) {
    $relative = [System.IO.Path]::GetRelativePath($ProjectRoot, $file.FullName)
    foreach ($rule in $riskyNames) {
      if ($file.Name -match $rule) {
        $issues.Add([pscustomobject]@{ path = $relative; type = "risky_filename"; rule = $rule }) | Out-Null
        break
      }
    }

    if ($file.Length -gt 1048576) {
      continue
    }

    try {
      $text = Get-Content -Raw -LiteralPath $file.FullName -ErrorAction Stop
    } catch {
      continue
    }

    foreach ($rule in $patterns) {
      if ($text -match $rule.pattern) {
        $issues.Add([pscustomobject]@{ path = $relative; type = "content_pattern"; rule = $rule.name }) | Out-Null
      }
    }

    if ($issues.Count -ge 50) {
      break
    }
  }

  $result = [ordered]@{
    created_at = (Get-Date).ToString("o")
    project_root = $ProjectRoot
    issue_count = $issues.Count
    allowed = [bool]$Allow
    issues = $issues.ToArray()
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

function Get-GitText {
  param(
    [string]$ProjectRoot,
    [string[]]$Args
  )

  try {
    $output = & git -C $ProjectRoot @Args 2>$null
    if ($LASTEXITCODE -eq 0) {
      return ($output -join "`n")
    }
  } catch {
  }
  return ""
}

function Get-ProjectTree {
  param([string]$ProjectRoot)

  $skipDirs = @(".git", "node_modules", ".venv", "venv", "__pycache__", "dist", "build", "target", ".next", ".cache", ".codegraph")
  $items = Get-ChildItem -LiteralPath $ProjectRoot -Force -ErrorAction SilentlyContinue |
    Where-Object { -not ($skipDirs -contains $_.Name) } |
    Select-Object -First 80
  return ($items | ForEach-Object {
    if ($_.PSIsContainer) { "[dir]  " + $_.Name } else { "[file] " + $_.Name }
  }) -join "`n"
}

function New-ReviewReport {
  param(
    [string]$ProjectRoot,
    [string]$ScanPath
  )

  $paths = Get-BridgePaths $ProjectRoot
  $stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
  $id = "codex-review-$stamp"
  $reportPath = Join-Path $paths.Reports "$stamp-review-request.md"
  $relativeReport = [System.IO.Path]::GetRelativePath($ProjectRoot, $reportPath)
  $gitStatus = Get-GitText $ProjectRoot @("status", "--short")
  if (-not $gitStatus) { $gitStatus = "(not a git repo or no git status available)" }
  $recentCommits = Get-GitText $ProjectRoot @("log", "--oneline", "-5")
  if (-not $recentCommits) { $recentCommits = "(not available)" }
  $tree = Get-ProjectTree $ProjectRoot
  $existingReports = Get-ChildItem -LiteralPath $paths.Reports -File -Filter "*.md" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -ne $reportPath } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 10 |
    ForEach-Object { [System.IO.Path]::GetRelativePath($ProjectRoot, $_.FullName) }

  $body = @"
# Codex Report: GPT Pro Review Request

- id: $id
- created_at: $(Get-Date -Format o)
- source: codex
- target: gpt-pro
- status: ready_for_review
- related_files:
  - $relativeReport

## Requested Feedback

Review the current project state through DevSpace. Focus on correctness, missing risks, test gaps, privacy/security concerns, and whether Codex should proceed with the next implementation round.

Write feedback only under `docs/ai-bridge/gpt-pro-feedback/`.

## Project Root

```text
$ProjectRoot
```

## Current Top-Level Files

```text
$tree
```

## Git Status

```text
$gitStatus
```

## Recent Commits

```text
$recentCommits
```

## Existing Codex Reports

```text
$($existingReports -join "`n")
```

## Security Scan

```text
$ScanPath
```

## Notes For GPT Pro

- You may inspect project files through DevSpace because the user selected `whole_project` review scope.
- Do not edit source, config, tests, docs outside `docs/ai-bridge/gpt-pro-feedback/`.
- Return a clear verdict, concerns, recommendations, and accepted/rejected actions for Codex.
"@

  Set-Content -LiteralPath $reportPath -Encoding UTF8 -Value $body
  Add-StateItem $ProjectRoot "pending_for_gpt" ([System.IO.Path]::GetRelativePath($ProjectRoot, $reportPath))
  Write-Host "Review report created: $reportPath" -ForegroundColor Green
  return $reportPath
}

function Get-FileSnapshot {
  param([string]$ProjectRoot)

  $skipDirs = @(".git", "node_modules", ".venv", "venv", "__pycache__", "dist", "build", "target", ".next", ".cache", ".codegraph")
  $files = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -File -Force -ErrorAction SilentlyContinue |
    Where-Object {
      $relative = [System.IO.Path]::GetRelativePath($ProjectRoot, $_.FullName)
      $parts = $relative -split "[\\/]"
      -not ($parts | Where-Object { $skipDirs -contains $_ })
    } |
    ForEach-Object {
      [pscustomobject]@{
        path = [System.IO.Path]::GetRelativePath($ProjectRoot, $_.FullName)
        length = $_.Length
        last_write_utc_ticks = $_.LastWriteTimeUtc.Ticks
      }
    }
  return @($files)
}

function Compare-Snapshots {
  param(
    $Before,
    $After
  )

  $beforeMap = @{}
  foreach ($item in $Before) { $beforeMap[$item.path] = $item }
  $changes = New-Object System.Collections.Generic.List[object]

  foreach ($item in $After) {
    if (-not $beforeMap.ContainsKey($item.path)) {
      $changes.Add([pscustomobject]@{ path = $item.path; change = "added" }) | Out-Null
      continue
    }
    $old = $beforeMap[$item.path]
    $oldWrite = if ($null -ne $old.last_write_utc_ticks) { [int64]$old.last_write_utc_ticks } else { [string]$old.last_write_utc }
    $newWrite = if ($null -ne $item.last_write_utc_ticks) { [int64]$item.last_write_utc_ticks } else { [string]$item.last_write_utc }
    if ($old.length -ne $item.length -or $oldWrite -ne $newWrite) {
      $changes.Add([pscustomobject]@{ path = $item.path; change = "modified" }) | Out-Null
    }
    $beforeMap.Remove($item.path)
  }

  foreach ($key in $beforeMap.Keys) {
    $changes.Add([pscustomobject]@{ path = $key; change = "deleted" }) | Out-Null
  }
  return $changes.ToArray()
}

function Get-OwnerToken {
  param($Runtime)

  if (Test-Path -LiteralPath $Runtime.OwnerToken) {
    return (Get-Content -Raw -LiteralPath $Runtime.OwnerToken).Trim()
  }

  New-Item -ItemType Directory -Path (Split-Path -Parent $Runtime.OwnerToken) -Force | Out-Null
  $bytes = New-Object byte[] 32
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  $token = [Convert]::ToBase64String($bytes)
  Set-Content -LiteralPath $Runtime.OwnerToken -Encoding ASCII -Value $token
  return $token
}

function Start-LoggedProcess {
  param(
    [string]$Name,
    [string]$FilePath,
    [string[]]$ArgumentList,
    [string]$LogDir
  )

  New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
  $out = Join-Path $LogDir "$Name.out.log"
  $err = Join-Path $LogDir "$Name.err.log"
  Remove-Item -LiteralPath $out, $err -Force -ErrorAction SilentlyContinue
  return Start-Process -FilePath $FilePath -ArgumentList $ArgumentList -RedirectStandardOutput $out -RedirectStandardError $err -WindowStyle Hidden -PassThru
}

function Get-NpxPath {
  $cmd = Get-Command "npx.cmd" -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  $cmd = Get-Command "npx" -ErrorAction SilentlyContinue
  if ($cmd) { return $cmd.Source }
  throw "npx was not found. Install Node/npm first."
}

function Wait-ForTunnelUrl {
  param(
    [string]$LogDir,
    [int]$TimeoutSeconds
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $pattern = "https://[A-Za-z0-9-]+\.trycloudflare\.com"
  while ((Get-Date) -lt $deadline) {
    foreach ($file in Get-ChildItem -LiteralPath $LogDir -Filter "cloudflared.*.log" -ErrorAction SilentlyContinue) {
      $text = Get-Content -Raw -LiteralPath $file.FullName -ErrorAction SilentlyContinue
      if (-not $text) {
        continue
      }
      $match = [regex]::Match($text, $pattern)
      if ($match.Success) {
        return $match.Value
      }
    }
    Start-Sleep -Seconds 2
  }
  throw "Timed out waiting for Cloudflare quick tunnel URL. Check logs in $LogDir."
}

function Wait-ForHttpStatus {
  param(
    [string]$Uri,
    [int]$Expected,
    [int]$TimeoutSeconds,
    [string]$Method = "Get"
  )

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    try {
      $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -Method $Method -TimeoutSec 8
      $code = [int]$response.StatusCode
    } catch {
      if ($_.Exception.Response) {
        $code = [int]$_.Exception.Response.StatusCode
      } else {
        $code = $null
      }
    }

    if ($code -eq $Expected) {
      return $true
    }
    Start-Sleep -Seconds 2
  }
  throw "Timed out waiting for $Uri to return HTTP $Expected."
}

function Stop-ProcessTree {
  param([int]$ProcessId)

  $children = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object { $_.ParentProcessId -eq $ProcessId })
  foreach ($child in $children) {
    Stop-ProcessTree ([int]$child.ProcessId)
  }
  Stop-Process -Id $ProcessId -Force -ErrorAction SilentlyContinue
}

function Stop-ProcessesByCommandPattern {
  param([string]$Pattern)

  $matches = @(Get-CimInstance Win32_Process -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -and $_.CommandLine -match $Pattern
  })
  foreach ($proc in $matches) {
    Stop-ProcessTree ([int]$proc.ProcessId)
  }
}

function Stop-Session {
  param(
    [string]$ProjectRoot,
    [switch]$IncludeDevSpace
  )

  $runtime = Get-RuntimePaths $ProjectRoot
  if (-not (Test-Path -LiteralPath $runtime.Session)) {
    Write-Host "No session file found: $($runtime.Session)"
    return
  }
  $session = Read-JsonFile $runtime.Session
  $pids = @($session.cloudflared_pid)
  if ($IncludeDevSpace) {
    $pids += @($session.devspace_pid)
  }
  foreach ($pidValue in $pids) {
    if ($pidValue) {
      Stop-ProcessTree ([int]$pidValue)
    }
  }
  if ($session.local_port) {
    Stop-ProcessesByCommandPattern ("127\.0\.0\.1:" + [regex]::Escape([string]$session.local_port))
  }
  if ($session.PSObject.Properties.Name -contains "stopped_at") {
    $session.stopped_at = (Get-Date).ToString("o")
  } else {
    $session | Add-Member -NotePropertyName "stopped_at" -NotePropertyValue (Get-Date).ToString("o")
  }
  ConvertTo-JsonFile $session $runtime.Session
  Set-ActiveSession $ProjectRoot $null
  Write-Host "Stopped review-loop session. Tunnel process stopped. DevSpace stopped: $([bool]$IncludeDevSpace)" -ForegroundColor Green
}

function Start-Session {
  param(
    [string]$ProjectRoot,
    [int]$LocalPort
  )

  Write-Host "Starting GPT Pro review session for: $ProjectRoot"
  $runtime = Get-RuntimePaths $ProjectRoot
  $paths = Get-BridgePaths $ProjectRoot
  $config = Get-Config $ProjectRoot
  $targetChatGptProjectUrl = $config.target_chatgpt_project_url
  if (-not $targetChatGptProjectUrl -and $config.target_chatgpt_url) {
    $targetChatGptProjectUrl = ConvertTo-ChatGptProjectUrl $config.target_chatgpt_url
  }
  if (-not $targetChatGptProjectUrl -or $targetChatGptProjectUrl -notmatch "^https://chatgpt\.com/") {
    throw "project-config.json must contain a ChatGPT project or new-chat URL in target_chatgpt_project_url."
  }
  if (Test-ChatGptConversationUrl $targetChatGptProjectUrl) {
    throw "Refusing to send to an existing ChatGPT /c/ conversation URL because DevSpace apps may not attach there. Re-run Init with a ChatGPT project or new-chat URL."
  }

  foreach ($dir in @($runtime.Base, $runtime.Logs, $runtime.DevspaceConfig, $runtime.DevspaceState, $runtime.Worktrees)) {
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
  }

  $npx = Get-NpxPath
  $cloudflared = $null
  $devspace = $null
  $startedOk = $false
  Write-Host "Starting Cloudflare quick tunnel on local port $LocalPort..."
  $cloudflared = Start-LoggedProcess -Name "cloudflared" -FilePath $npx -ArgumentList @("--yes", "cloudflared", "tunnel", "--url", "http://127.0.0.1:$LocalPort", "--no-autoupdate") -LogDir $runtime.Logs
  try {
    $tunnelUrl = Wait-ForTunnelUrl $runtime.Logs $TunnelTimeoutSeconds
    $mcpUrl = "$tunnelUrl/mcp"
    Write-Host "Quick tunnel URL: $tunnelUrl"

    $ownerToken = Get-OwnerToken $runtime
    $oldEnv = @{
      PORT = $env:PORT
      DEVSPACE_ALLOWED_ROOTS = $env:DEVSPACE_ALLOWED_ROOTS
      DEVSPACE_PUBLIC_BASE_URL = $env:DEVSPACE_PUBLIC_BASE_URL
      DEVSPACE_OAUTH_OWNER_TOKEN = $env:DEVSPACE_OAUTH_OWNER_TOKEN
      DEVSPACE_CONFIG_DIR = $env:DEVSPACE_CONFIG_DIR
      DEVSPACE_STATE_DIR = $env:DEVSPACE_STATE_DIR
      DEVSPACE_WORKTREE_ROOT = $env:DEVSPACE_WORKTREE_ROOT
      DEVSPACE_TOOL_MODE = $env:DEVSPACE_TOOL_MODE
      DEVSPACE_LOG_SHELL_COMMANDS = $env:DEVSPACE_LOG_SHELL_COMMANDS
    }

    try {
      $env:PORT = [string]$LocalPort
      $env:DEVSPACE_ALLOWED_ROOTS = $ProjectRoot
      $env:DEVSPACE_PUBLIC_BASE_URL = $tunnelUrl
      $env:DEVSPACE_OAUTH_OWNER_TOKEN = $ownerToken
      $env:DEVSPACE_CONFIG_DIR = $runtime.DevspaceConfig
      $env:DEVSPACE_STATE_DIR = $runtime.DevspaceState
      $env:DEVSPACE_WORKTREE_ROOT = $runtime.Worktrees
      $env:DEVSPACE_TOOL_MODE = "full"
      $env:DEVSPACE_LOG_SHELL_COMMANDS = "0"

      Write-Host "Starting DevSpace MCP server..."
      $devspace = Start-LoggedProcess -Name "devspace" -FilePath $npx -ArgumentList @("--yes", "@waishnav/devspace", "serve") -LogDir $runtime.Logs
    } finally {
      foreach ($key in $oldEnv.Keys) {
        if ($null -eq $oldEnv[$key]) {
          Remove-Item -Path "Env:$key" -ErrorAction SilentlyContinue
        } else {
          Set-Item -Path "Env:$key" -Value $oldEnv[$key] -ErrorAction SilentlyContinue
        }
      }
    }

    Write-Host "Checking local and public health endpoints..."
    Wait-ForHttpStatus "http://127.0.0.1:$LocalPort/healthz" 200 $StartupTimeoutSeconds | Out-Null
    Wait-ForHttpStatus "$tunnelUrl/healthz" 200 $StartupTimeoutSeconds | Out-Null
    Wait-ForHttpStatus $mcpUrl 401 $StartupTimeoutSeconds "Post" | Out-Null
    $oauthDiscovery = Invoke-OAuthDiscoveryCheck $tunnelUrl $mcpUrl 20
    if (-not $oauthDiscovery.ok) {
      throw "OAuth discovery check failed: $($oauthDiscovery.error)"
    }

    $latestReport = Get-ChildItem -LiteralPath $paths.Reports -File -Filter "*-review-request.md" |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1
    if (-not $latestReport) {
      throw "No review report found. Run -Action Prepare first."
    }

    $feedbackName = ($latestReport.BaseName -replace "-review-request$", "") + "-gpt-pro-feedback.md"
    $feedbackRelative = "docs/ai-bridge/gpt-pro-feedback/$feedbackName"
    $promptPath = Join-Path $paths.Inbox ((Get-Date -Format "yyyy-MM-dd-HHmmss") + "-chatgpt-review-prompt.md")
    $reportRelative = [System.IO.Path]::GetRelativePath($ProjectRoot, $latestReport.FullName)

    $prompt = @"
Use DevSpace AI Bridge to review this Codex project.

Current MCP URL: $mcpUrl
Project root to open in DevSpace: $ProjectRoot
Review report to read first: $reportRelative
Write your feedback file exactly here: $feedbackRelative

Connector preflight is mandatory before review:
1. Confirm the DevSpace AI Bridge app/tool is available in this new ChatGPT chat.
2. Confirm the active DevSpace connector points to the current MCP URL above.
3. Open the project root above and read the review report above.
4. If any preflight step fails, write a BLOCKED feedback file if possible. If you cannot write the file, reply BLOCKED in chat and do not invent review findings.
5. Continue to source review only after the preflight succeeds.

Review scope:
- You may inspect files in the opened project because the user selected whole_project scope.
- Do not edit source code, tests, configs, or docs outside docs/ai-bridge/gpt-pro-feedback/.
- If the connector is not available or does not point to the current MCP URL, say that clearly and do not invent review results.

Feedback format:
- Verdict
- Blocking concerns
- Non-blocking concerns
- Recommended Codex actions
- Tests or verification you expect Codex to run
- Anything that should be rejected or deferred
"@
    Set-Content -LiteralPath $promptPath -Encoding UTF8 -Value $prompt

    $session = [ordered]@{
      started_at = (Get-Date).ToString("o")
      project_root = $ProjectRoot
      local_port = $LocalPort
      tunnel_url = $tunnelUrl
      mcp_url = $mcpUrl
      target_chatgpt_project_url = $targetChatGptProjectUrl
      target_chatgpt_url = $targetChatGptProjectUrl
      conversation_policy = "new_chat_per_review_round"
      connector_preflight_required = $true
      oauth_discovery = $oauthDiscovery
      connector_preflight = [ordered]@{
        status = "not_started"
        reason = $null
        checked_at = $null
      }
      owner_token_path = $runtime.OwnerToken
      prompt_path = $promptPath
      report_path = $latestReport.FullName
      expected_feedback_path = Join-Path $ProjectRoot $feedbackRelative
      cloudflared_pid = $cloudflared.Id
      devspace_pid = $devspace.Id
      logs = $runtime.Logs
    }
    ConvertTo-JsonFile $session $runtime.Session
    Set-ActiveSession $ProjectRoot $session
    $baseline = Get-FileSnapshot $ProjectRoot
    ConvertTo-JsonFile $baseline $runtime.Baseline
    $startedOk = $true

    Write-Host "Review session started." -ForegroundColor Green
    Write-Host "MCP URL: $mcpUrl"
    Write-Host "OAuth discovery: OK"
    Write-Host "Owner token path: $($runtime.OwnerToken)"
    Write-Host "Prompt file: $promptPath"
    Write-Host "Expected feedback: $($session.expected_feedback_path)"
    return $session
  } finally {
    if (-not $startedOk) {
      if ($devspace) {
        Stop-ProcessTree $devspace.Id
      }
      if ($cloudflared) {
        Stop-ProcessTree $cloudflared.Id
      }
      Stop-ProcessesByCommandPattern ("127\.0\.0\.1:" + [regex]::Escape([string]$LocalPort))
    }
  }
}

function Wait-ConnectorPreflight {
  param(
    [string]$ProjectRoot,
    [int]$TimeoutSeconds
  )

  $session = Get-RunningSession $ProjectRoot
  $logPath = Join-Path $session.logs "devspace.out.log"

  try {
    Wait-ForHttpStatus ("http://127.0.0.1:{0}/healthz" -f $session.local_port) 200 10 | Out-Null
    Wait-ForHttpStatus ("{0}/healthz" -f $session.tunnel_url) 200 20 | Out-Null
    $oauthDiscovery = Invoke-OAuthDiscoveryCheck $session.tunnel_url $session.mcp_url 20
    if (-not $oauthDiscovery.ok) {
      throw "OAuth discovery failed: $($oauthDiscovery.error)"
    }
    Set-ObjectProperty $session "oauth_discovery" $oauthDiscovery
    Save-Session $ProjectRoot $session
  } catch {
    $reason = if ($_.Exception.Message -match "OAuth discovery") { "oauth_metadata_unreachable" } else { "devspace_or_tunnel_unreachable" }
    Set-ConnectorPreflight $ProjectRoot $session "blocked" $reason ([pscustomobject][ordered]@{
      mcp_url = $session.mcp_url
      local_port = $session.local_port
      tunnel_url = $session.tunnel_url
      next_action = "Start a fresh review session. Confirm /healthz and OAuth .well-known metadata are reachable before reconnecting ChatGPT."
      error = $_.Exception.Message
    })
    throw "Connector preflight cannot start because the DevSpace public endpoint is not fully reachable: $($_.Exception.Message)"
  }

  $startedAt = Get-Date
  Set-ConnectorPreflight $ProjectRoot $session "waiting" "waiting_for_chatgpt_request" ([pscustomobject][ordered]@{
    started_at = $startedAt.ToString("o")
    timeout_seconds = $TimeoutSeconds
    mcp_url = $session.mcp_url
    devspace_log = $logPath
    owner_token_path = $session.owner_token_path
    next_action = "In ChatGPT, disconnect or recreate the DevSpace app with this MCP URL, scan tools/connect, and enter the local Owner password from owner_token_path only in the DevSpace approval page."
  })

  Write-Host "Connector preflight waiting for ChatGPT to reach DevSpace." -ForegroundColor Yellow
  Write-Host "MCP URL: $($session.mcp_url)"
  Write-Host "Target ChatGPT project/new-chat URL: $($session.target_chatgpt_project_url)"
  Write-Host "Owner token path: $($session.owner_token_path)"
  Write-Host "Manual steps while this waits:"
  Write-Host "  1. In ChatGPT settings, disconnect or recreate the DevSpace app."
  Write-Host "  2. Set the app endpoint to the MCP URL above, then scan tools/connect."
  Write-Host "  3. If an Owner password page opens, paste the password from owner token path there only."
  Write-Host "  4. Open a new chat in the configured ChatGPT project."
  Write-Host "This check passes only after DevSpace logs a non-healthcheck request from ChatGPT."

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    $requests = @(Get-DevSpaceHttpRequests $logPath $startedAt)
    $candidates = @($requests | Where-Object { Test-ConnectorCandidateRequest $_ })
    if ($candidates.Count -gt 0) {
      $last = $candidates[-1]
      $session = Get-RunningSession $ProjectRoot
      $oauthFailures = @($candidates | Where-Object { Test-OAuthFailureRequest $_ })
      if ($oauthFailures.Count -gt 0) {
        $failure = $oauthFailures[-1]
        Set-ConnectorPreflight $ProjectRoot $session "blocked" "oauth_request_rejected" ([pscustomobject][ordered]@{
          started_at = $startedAt.ToString("o")
          completed_at = (Get-Date).ToString("o")
          timeout_seconds = $TimeoutSeconds
          mcp_url = $session.mcp_url
          devspace_log = $logPath
          observed_request_count = $candidates.Count
          observed_request = (Format-ObservedRequest $failure)
          next_action = "ChatGPT reached DevSpace, but an OAuth/connection request returned an error. Reconnect the app with the current MCP URL and complete Owner password approval."
        })
        throw "Connector preflight saw a ChatGPT-side OAuth request, but it was rejected: $($failure.method) $($failure.path) -> $($failure.status)"
      }
      Set-ConnectorPreflight $ProjectRoot $session "passed" "chatgpt_request_seen" ([pscustomobject][ordered]@{
        started_at = $startedAt.ToString("o")
        completed_at = (Get-Date).ToString("o")
        timeout_seconds = $TimeoutSeconds
        mcp_url = $session.mcp_url
        devspace_log = $logPath
        observed_request_count = $candidates.Count
        observed_request = (Format-ObservedRequest $last)
      })
      Write-Host "Connector preflight passed. DevSpace saw a ChatGPT-side request: $($last.method) $($last.path) -> $($last.status)" -ForegroundColor Green
      return
    }
    Start-Sleep -Seconds 3
  }

  $allRequests = @(Get-DevSpaceHttpRequests $logPath $startedAt)
  $healthOnlyRequests = @($allRequests | Where-Object { $_.path -eq "/healthz" })
  $session = Get-RunningSession $ProjectRoot
  Set-ConnectorPreflight $ProjectRoot $session "blocked" "no_chatgpt_request_seen" ([pscustomobject][ordered]@{
    started_at = $startedAt.ToString("o")
    completed_at = (Get-Date).ToString("o")
    timeout_seconds = $TimeoutSeconds
    mcp_url = $session.mcp_url
    devspace_log = $logPath
    total_http_requests_seen = $allRequests.Count
    healthcheck_requests_seen = $healthOnlyRequests.Count
    owner_token_path = $session.owner_token_path
    oauth_discovery_ok = [bool]($session.oauth_discovery -and $session.oauth_discovery.ok)
    next_action = "ChatGPT did not reach this DevSpace instance. Disconnect/recreate the app with the current MCP URL, scan tools/connect while the tunnel is running, and complete Owner password approval from owner_token_path."
  })
  throw "Connector preflight timed out. DevSpace did not see a ChatGPT-side request for the current MCP URL."
}

function Invoke-ConnectorPreflight {
  param(
    [string]$ProjectRoot,
    [int]$LocalPort,
    [int]$TimeoutSeconds
  )

  $runtime = Get-RuntimePaths $ProjectRoot
  $shouldStart = $true
  if (Test-Path -LiteralPath $runtime.Session) {
    $existing = Read-JsonFile $runtime.Session
    $shouldStart = ($existing.PSObject.Properties.Name -contains "stopped_at" -and $existing.stopped_at)
  }
  if ($shouldStart) {
    Start-Session $ProjectRoot $LocalPort | Out-Null
  }
  try {
    Wait-ConnectorPreflight $ProjectRoot $TimeoutSeconds
  } catch {
    Stop-Session $ProjectRoot -IncludeDevSpace:$true
    throw
  }
}

function Send-Prompt {
  param(
    [string]$ProjectRoot,
    [switch]$Submit
  )

  $session = Get-RunningSession $ProjectRoot
  if (-not $session.connector_preflight -or $session.connector_preflight.status -ne "passed") {
    throw "Connector preflight has not passed. Run -Action PreflightConnector and reconnect the DevSpace app before SendPrompt."
  }
  $chatUrl = $session.target_chatgpt_project_url
  if (-not $chatUrl) {
    $chatUrl = $session.target_chatgpt_url
  }
  if (Test-ChatGptConversationUrl $chatUrl) {
    throw "Refusing to open an existing ChatGPT /c/ conversation URL. Start from the project or new-chat URL so DevSpace can attach to the new chat."
  }
  $helper = Join-Path $PSScriptRoot "edge_send_review_prompt.py"
  $python = Join-Path $env:USERPROFILE ".agents\skills\browser-use\scripts\.venv\Scripts\python.exe"
  if (-not (Test-Path -LiteralPath $python)) {
    $python = (Get-Command python -ErrorAction Stop).Source
  }

  $args = @($helper, "--chat-url", $chatUrl, "--prompt-file", $session.prompt_path, "--require-new-chat")
  if ($Submit) {
    $args += "--send"
  }

  & $python @args
  if ($LASTEXITCODE -ne 0) {
    throw "Browser prompt helper failed with exit code $LASTEXITCODE."
  }
}

function Wait-Feedback {
  param(
    [string]$ProjectRoot,
    [int]$TimeoutSeconds
  )

  $runtime = Get-RuntimePaths $ProjectRoot
  $paths = Get-BridgePaths $ProjectRoot
  $session = Get-RunningSession $ProjectRoot
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $feedbackFile = $null

  while ((Get-Date) -lt $deadline) {
    $candidates = Get-ChildItem -LiteralPath $paths.Feedback -File -Filter "*.md" -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTime -gt ([datetime]$session.started_at) } |
      Sort-Object LastWriteTime -Descending
    if ($candidates) {
      $feedbackFile = $candidates[0]
      break
    }
    Start-Sleep -Seconds 5
  }

  if (-not $feedbackFile) {
    throw "Timed out waiting for GPT Pro feedback in $($paths.Feedback)."
  }

  $before = @()
  if (Test-Path -LiteralPath $runtime.Baseline) {
    $before = @(Read-JsonFile $runtime.Baseline)
  }
  $after = Get-FileSnapshot $ProjectRoot
  $changes = Compare-Snapshots $before $after
  $allowedPrefix = "docs\ai-bridge\gpt-pro-feedback\"
  $outOfBounds = @($changes | Where-Object {
    $path = $_.path -replace "/", "\"
    -not $path.StartsWith($allowedPrefix, [System.StringComparison]::OrdinalIgnoreCase)
  })

  $summary = [ordered]@{
    feedback_path = $feedbackFile.FullName
    changed_files = [object[]]$changes
    out_of_bounds_writes = [object[]]$outOfBounds
    checked_at = (Get-Date).ToString("o")
  }
  $summaryPath = Join-Path $runtime.Base "last-feedback-summary.json"
  ConvertTo-JsonFile $summary $summaryPath

  Write-Host "Feedback detected: $($feedbackFile.FullName)" -ForegroundColor Green
  if ($outOfBounds.Count -gt 0) {
    Write-Host "Out-of-bounds writes detected:" -ForegroundColor Red
    foreach ($item in $outOfBounds) {
      Write-Host (" - {0} ({1})" -f $item.path, $item.change) -ForegroundColor Red
    }
    throw "GPT changed files outside the feedback directory. Pause before acting."
  }

  Add-StateItem $ProjectRoot "pending_for_codex" ([System.IO.Path]::GetRelativePath($ProjectRoot, $feedbackFile.FullName))
  Write-Host "No out-of-bounds writes detected." -ForegroundColor Green
  Write-Host "Summary: $summaryPath"
  return $feedbackFile.FullName
}

function Get-LatestBridgeFile {
  param(
    [string]$Directory,
    [string]$Filter = "*.md"
  )

  if (-not (Test-Path -LiteralPath $Directory)) {
    return $null
  }

  return Get-ChildItem -LiteralPath $Directory -File -Filter $Filter -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -ne "README.md" } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function New-ExperienceRecord {
  param(
    [string]$ProjectRoot,
    [string]$Outcome,
    [string]$Lesson,
    [string]$Notes
  )

  Ensure-Bridge $ProjectRoot $null | Out-Null
  $paths = Get-BridgePaths $ProjectRoot
  [string]$experienceLogPath = if ($paths.ExperienceLog) { [string]$paths.ExperienceLog } else { [System.IO.Path]::Combine([string]$paths.Bridge, "experience-log.md") }
  [string]$experienceIssuesPath = if ($paths.ExperienceIssues) { [string]$paths.ExperienceIssues } else { [System.IO.Path]::Combine([string]$paths.Bridge, "experience-issues") }
  if ([string]::IsNullOrWhiteSpace($experienceLogPath) -or [string]::IsNullOrWhiteSpace($experienceIssuesPath)) {
    throw "Experience paths did not resolve for project root: $ProjectRoot"
  }
  if (-not (Test-Path -LiteralPath $experienceIssuesPath)) {
    New-Item -ItemType Directory -Path $experienceIssuesPath -Force | Out-Null
  }
  if (-not (Test-Path -LiteralPath $experienceLogPath)) {
    Set-Content -LiteralPath $experienceLogPath -Encoding UTF8 -Value "# GPT Pro Review Loop Experience Log`n"
  }
  $stamp = Get-Date -Format "yyyy-MM-dd-HHmmss"
  $projectName = Split-Path -Leaf $ProjectRoot
  $latestReport = Get-LatestBridgeFile $paths.Reports
  $latestFeedback = Get-LatestBridgeFile $paths.Feedback
  $reportRel = if ($latestReport) { [System.IO.Path]::GetRelativePath($ProjectRoot, $latestReport.FullName) } else { "(none)" }
  $feedbackRel = if ($latestFeedback) { [System.IO.Path]::GetRelativePath($ProjectRoot, $latestFeedback.FullName) } else { "(none)" }
  $safeLesson = if ($Lesson) { $Lesson } else { "(fill in the reusable lesson)" }
  $safeNotes = if ($Notes) { $Notes } else { "(fill in what happened, without secrets or private data)" }
  $safeOutcome = if ($Outcome) { $Outcome } else { "unspecified" }
  $gitStatus = Get-GitText $ProjectRoot @("status", "--short")
  if (-not $gitStatus) { $gitStatus = "(not available)" }

  $entryLines = @(
    "",
    "## $stamp",
    "",
    "- outcome: $safeOutcome",
    "- latest_report: $reportRel",
    "- latest_feedback: $feedbackRel",
    "",
    "### Notes",
    "",
    $safeNotes,
    "",
    "### Reusable Lesson",
    "",
    $safeLesson,
    "",
    "### Local Git Status At Capture",
    "",
    '```text',
    $gitStatus,
    '```'
  )
  Add-Content -LiteralPath $experienceLogPath -Encoding UTF8 -Value ($entryLines -join [Environment]::NewLine)

  [string]$issueFileName = "{0}-github-issue-draft.md" -f $stamp
  [string]$issuePath = "$experienceIssuesPath\$issueFileName"
  if ([string]::IsNullOrWhiteSpace($issuePath)) {
    throw "Experience issue draft path did not resolve."
  }
  $issueLines = @(
    "# [experience] $projectName - $safeOutcome",
    "",
    "## Scenario",
    "",
    'Project-local use of `gpt-pro-review-loop`.',
    "",
    "## Observed behavior",
    "",
    $safeNotes,
    "",
    "## Reusable lesson",
    "",
    $safeLesson,
    "",
    "## Local evidence",
    "",
    "- Latest Codex report: $reportRel",
    "- Latest GPT Pro feedback: $feedbackRel",
    "",
    "## Privacy check",
    "",
    "This draft should contain only process-level experience. Do not paste API keys, cookies, OAuth tokens, owner tokens, private account data, proprietary source snippets, or private business data into the public GitHub issue."
  )
  [System.IO.File]::WriteAllLines($issuePath, [string[]]$issueLines, [System.Text.Encoding]::UTF8)

  Write-Host "Experience recorded: $experienceLogPath" -ForegroundColor Green
  Write-Host "GitHub issue draft created: $issuePath" -ForegroundColor Green
  return $issuePath
}

function Show-Status {
  param([string]$ProjectRoot)

  $runtime = Get-RuntimePaths $ProjectRoot
  $paths = Get-BridgePaths $ProjectRoot
  $session = $null
  if (Test-Path -LiteralPath $runtime.Session) {
    $session = Read-JsonFile $runtime.Session
  }
  $sessionActive = ($null -ne $session -and -not ($session.PSObject.Properties.Name -contains "stopped_at" -and $session.stopped_at))
  [pscustomobject]@{
    project_root = $ProjectRoot
    bridge_exists = (Test-Path -LiteralPath $paths.Bridge)
    config_path = $paths.Config
    session_path = $runtime.Session
    session_active = $sessionActive
    logs = $runtime.Logs
  } | Format-List

  if ($session) {
    $session | Format-List
  }
}

$ProjectRoot = Resolve-ProjectRoot $Root

switch ($Action) {
  "Init" {
    Ensure-Bridge $ProjectRoot $TargetChatGptUrl | Out-Null
    Write-Host "AI bridge initialized for: $ProjectRoot" -ForegroundColor Green
  }
  "Prepare" {
    Ensure-Bridge $ProjectRoot $TargetChatGptUrl | Out-Null
    $scan = Invoke-SensitiveScan $ProjectRoot -Allow:$AllowSensitive
    New-ReviewReport $ProjectRoot $scan | Out-Null
  }
  "StartSession" {
    Ensure-Bridge $ProjectRoot $TargetChatGptUrl | Out-Null
    Start-Session $ProjectRoot $Port | Out-Null
  }
  "PreflightConnector" {
    Ensure-Bridge $ProjectRoot $TargetChatGptUrl | Out-Null
    Invoke-ConnectorPreflight $ProjectRoot $Port $ConnectorTimeoutSeconds
  }
  "SendPrompt" {
    Send-Prompt $ProjectRoot -Submit:$Send
  }
  "WaitFeedback" {
    Wait-Feedback $ProjectRoot $FeedbackTimeoutSeconds | Out-Null
  }
  "RecordExperience" {
    New-ExperienceRecord $ProjectRoot $ExperienceOutcome $ExperienceLesson $ExperienceNotes | Out-Null
  }
  "StopSession" {
    Stop-Session $ProjectRoot -IncludeDevSpace:$StopDevSpace
  }
  "Status" {
    Show-Status $ProjectRoot
  }
  "Run" {
    Ensure-Bridge $ProjectRoot $TargetChatGptUrl | Out-Null
    $scan = Invoke-SensitiveScan $ProjectRoot -Allow:$AllowSensitive
    New-ReviewReport $ProjectRoot $scan | Out-Null
    $sessionStarted = $false
    try {
      Start-Session $ProjectRoot $Port | Out-Null
      $sessionStarted = $true
      Wait-ConnectorPreflight $ProjectRoot $ConnectorTimeoutSeconds
      Send-Prompt $ProjectRoot -Submit:$Send
      Wait-Feedback $ProjectRoot $FeedbackTimeoutSeconds | Out-Null
    } catch {
      if ($sessionStarted) {
        Stop-Session $ProjectRoot -IncludeDevSpace:$true
      }
      throw
    }
  }
}

$global:LASTEXITCODE = 0
