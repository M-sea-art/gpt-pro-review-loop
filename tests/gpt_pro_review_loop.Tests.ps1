BeforeAll {
  $script:Root = Resolve-Path (Join-Path $PSScriptRoot "..")
  $script:Skill = Join-Path $script:Root "scripts/gpt_pro_review_loop.ps1"

  function New-TestProject {
    param([string]$Name = "project")
    $root = Join-Path ([System.IO.Path]::GetTempPath()) ("gpt-pro-review-loop-test-{0}-{1}" -f $Name, [guid]::NewGuid().ToString("N"))
    New-Item -ItemType Directory -Path $root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $root "src") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $root "README.md") -Encoding UTF8 -Value "# Test Project"
    Set-Content -LiteralPath (Join-Path $root "src/app.txt") -Encoding UTF8 -Value "hello"
    return $root
  }

  function Read-State {
    param([string]$ProjectRoot)
    Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot "docs/ai-review-loop/review-state.json") | ConvertFrom-Json
  }

  function Read-Config {
    param([string]$ProjectRoot)
    Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot "docs/ai-review-loop/project-config.json") | ConvertFrom-Json
  }
}

Describe "gpt-pro-review-loop state machine" {
  It "initializes complete config and state fields" {
    $project = New-TestProject "init"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"

    $config = Read-Config $project
    $state = Read-State $project

    $config.code_map_policy | Should -Be "filesystem_map_with_optional_codegraph_context"
    $config.codex_assessment_required | Should -BeTrue
    $config.feedback_return_policy | Should -Be "send_local_assessment_to_same_chat"
    $config.url_selection_policy | Should -Be "ask_once_when_missing_or_changed"
    $config.quota_mode | Should -Be "economy"
    $config.default_max_prompt_chars | Should -Be 8000
    $config.visual_evidence_policy | Should -Be "attach_only_when_requested_or_new_hash"
    $config.external_review_policy | Should -Be "send_only_when_new_evidence_or_explicit_review_needed"
    $state.PSObject.Properties.Name | Should -Contain "pending_prompts"
    $state.PSObject.Properties.Name | Should -Contain "captured_reviews"
    $state.PSObject.Properties.Name | Should -Contain "runtime_brief"
    $state.PSObject.Properties.Name | Should -Contain "browser_preflight_status"
    $state.PSObject.Properties.Name | Should -Contain "should_send_to_gpt"
    @($state.pending_prompts).Count | Should -Be 0
    @($state.captured_reviews).Count | Should -Be 0
    $state.baseline_sent_to_url | Should -Be $null
    $state.baseline_sent_hash | Should -Be $null
    $state.latest_prompt_target_url | Should -Be $null
    $state.latest_prompt_opened_tab_url | Should -Be $null
    $state.latest_assessment_target_url | Should -Be $null
    $state.latest_assessment_opened_tab_url | Should -Be $null
    $state.url_confirmation_required | Should -BeFalse
    $state.url_confirmation_reason | Should -Be $null
    $state.quota_mode | Should -Be "economy"
    $state.last_prompt_chars | Should -Be 0
    $state.cumulative_prompt_chars | Should -Be 0
    $state.should_send_to_gpt | Should -BeTrue
    $state.send_reason | Should -Be "initial_review"

    $statusText = (& $script:Skill -Action Status -Root $project | Out-String)
    $statusText | Should -Match "target_chatgpt_url"
    $statusText | Should -Match "https://chatgpt.com/g/test-project"
    $statusText | Should -Match "quota_mode"
  }

  It "rejects invalid ChatGPT URLs at init" {
    $project = New-TestProject "bad-url"
    { & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://example.com/not-chatgpt" } | Should -Throw
  }

  It "requires one-time target URL confirmation before prepare" {
    $project = New-TestProject "missing-url"
    & $script:Skill -Action Init -Root $project

    $state = Read-State $project
    $state.url_confirmation_required | Should -BeTrue
    $state.url_confirmation_reason | Should -Be "missing_target_chatgpt_url"

    { & $script:Skill -Action Prepare -Root $project } | Should -Throw -ExpectedMessage "*Ask the user once*"

    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    $state = Read-State $project
    $state.url_confirmation_required | Should -BeFalse
    $state.url_confirmation_reason | Should -Be $null
  }

  It "requires one-time confirmation after target URL changes outside Init" {
    $project = New-TestProject "changed-url"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/old-project"
    $configPath = Join-Path $project "docs/ai-review-loop/project-config.json"
    $config = Get-Content -Raw -LiteralPath $configPath | ConvertFrom-Json
    $config.target_chatgpt_conversation_url = "https://chatgpt.com/g/new-project"
    $config.target_chatgpt_url = "https://chatgpt.com/g/new-project"
    $config | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $configPath -Encoding UTF8

    { & $script:Skill -Action Prepare -Root $project } | Should -Throw -ExpectedMessage "*one-time user confirmation*"
    $state = Read-State $project
    $state.url_confirmation_required | Should -BeTrue
    $state.url_confirmation_reason | Should -Be "target_chatgpt_url_changed"

    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/new-project"
    $state = Read-State $project
    $state.url_confirmation_required | Should -BeFalse
  }

  It "prepares prompt queue without mixing prompt into review queue" {
    $project = New-TestProject "prepare"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project

    $state = Read-State $project
    @($state.pending_prompts).Count | Should -Be 1
    @($state.pending_reviews).Count | Should -Be 0
    $state.latest_prompt | Should -Match "^docs/ai-review-loop/prompts/"
  }

  It "creates compact prompts and runtime briefs in economy mode" {
    $project = New-TestProject "compact"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action PrepareCompactReview -Root $project -MaxPromptChars 4000

    $state = Read-State $project
    $promptPath = Join-Path $project ($state.latest_prompt -replace "/", "\")
    $prompt = Get-Content -Raw -LiteralPath $promptPath
    $prompt.Length | Should -BeLessOrEqual 4000
    $state.quota_mode | Should -Be "economy"
    $state.last_prompt_chars | Should -Be $prompt.Length
    $state.cumulative_prompt_chars | Should -BeGreaterThan 0
    $state.runtime_brief | Should -Match "^docs/ai-review-loop/loop-runs/"
    $briefPath = Join-Path $project ($state.runtime_brief -replace "/", "\")
    $brief = Get-Content -Raw -LiteralPath $briefPath | ConvertFrom-Json
    $brief.latest_prompt | Should -Be $state.latest_prompt
    $brief.quota_mode | Should -Be "economy"
  }

  It "records browser preflight once per iteration" {
    $project = New-TestProject "preflight"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action PreflightBrowser -Root $project

    $first = Read-State $project
    $first.browser_preflight_status | Should -Be "pending_edge_browser_control"
    $first.browser_backend_type | Should -Be "codex_edge_chrome_extension_backend"
    $first.browser_preflight_iteration | Should -Be 0
    $firstCheckedAt = $first.browser_preflight_checked_at

    & $script:Skill -Action PreflightBrowser -Root $project
    $second = Read-State $project
    $second.browser_preflight_checked_at | Should -Be $firstCheckedAt
    $second.runtime_brief | Should -Match "^docs/ai-review-loop/loop-runs/"
  }

  It "records baseline target and hash after prompt send" {
    $project = New-TestProject "send"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action SendPrompt -Root $project -Send -OpenedTabUrl "https://chatgpt.com/g/test-project/c/abc123"

    $state = Read-State $project
    $state.baseline_sent | Should -BeTrue
    $state.baseline_sent_to_url | Should -Be "https://chatgpt.com/g/test-project"
    $state.baseline_sent_hash | Should -Be $state.baseline_hash
    $state.latest_prompt_target_url | Should -Be "https://chatgpt.com/g/test-project"
    $state.latest_prompt_opened_tab_url | Should -Be "https://chatgpt.com/g/test-project/c/abc123"
  }

  It "deduplicates visual evidence hash when explicitly attached" {
    $project = New-TestProject "visual-hash"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    $statePath = Join-Path $project "docs/ai-review-loop/review-state.json"
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    $state.latest_visual_evidence_hash = "abc123"
    $state.latest_visual_evidence_path = "evidence/contact-sheet.png"
    $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding UTF8

    & $script:Skill -Action SendPrompt -Root $project -Send -AttachVisualEvidence
    $state = Read-State $project
    $state.last_visual_evidence_sent_hash | Should -Be "abc123"
  }

  It "records actual ChatGPT tab URL after assessment send" {
    $project = New-TestProject "assessment-url"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer gpt-pro -Phase initial -ReviewText "review"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict CONTINUE -NextAction "collect_evidence"
    & $script:Skill -Action SendAssessment -Root $project -Send -OpenedTabUrl "https://chatgpt.com/g/test-project/c/abc123"

    $state = Read-State $project
    $state.latest_assessment_target_url | Should -Be "https://chatgpt.com/g/test-project"
    $state.latest_assessment_opened_tab_url | Should -Be "https://chatgpt.com/g/test-project/c/abc123"
    $state.next_action | Should -Be "capture_gpt_pro_recheck"
  }

  It "rejects non-ChatGPT opened tab URLs" {
    $project = New-TestProject "bad-opened-url"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project

    { & $script:Skill -Action SendPrompt -Root $project -Send -OpenedTabUrl "https://example.com/not-chatgpt" } | Should -Throw
  }

  It "resets baseline when target URL changes" {
    $project = New-TestProject "url-change"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/old-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action SendPrompt -Root $project -Send
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/new-project"

    $state = Read-State $project
    $state.baseline_sent | Should -BeFalse
    $state.baseline_sent_to_url | Should -Be $null
    $state.baseline_sent_hash | Should -Be $null
  }

  It "force baseline keeps full baseline in the next prompt" {
    $project = New-TestProject "force-baseline"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action SendPrompt -Root $project -Send
    & $script:Skill -Action Prepare -Root $project -ForceBaseline

    $state = Read-State $project
    $promptPath = Join-Path $project ($state.latest_prompt -replace "/", "\")
    (Get-Content -Raw -LiteralPath $promptPath) | Should -Match "ForceBaseline"
  }

  It "does not overwrite repeated reviews or assessments" {
    $project = New-TestProject "overwrite"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer gpt-pro -Phase initial -ReviewText "first"
    & $script:Skill -Action CaptureReview -Root $project -Reviewer gpt-pro -Phase initial -ReviewText "second"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict CONTINUE -NextAction "collect_evidence"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict CONTINUE -NextAction "collect_evidence"

    @(Get-ChildItem -LiteralPath (Join-Path $project "docs/ai-review-loop/reviews") -Filter "*.md").Count | Should -Be 2
    @(Get-ChildItem -LiteralPath (Join-Path $project "docs/ai-review-loop/assessments") -Filter "*.md").Count | Should -Be 2
    $state = Read-State $project
    @($state.captured_reviews).Count | Should -Be 2
  }

  It "maps terminal next decisions" {
    $project = New-TestProject "decision"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "done"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "final_report"
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "complete"
    $state.stop_reason | Should -Be "goal_achieved"
    $state.continuation_required | Should -BeFalse
  }

  It "requires continuation when next decision is still running" {
    $project = New-TestProject "continue-decision"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "continue"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict CONTINUE -NextAction "polish_pass"
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.stop_reason | Should -Be $null
    $state.continuation_required | Should -BeTrue
    $state.should_send_to_gpt | Should -BeFalse
    $state.send_reason | Should -Be "local_only_continue"
    $state.local_only_next_action | Should -Be "polish_pass"
    $run = Get-ChildItem -LiteralPath (Join-Path $project "docs/ai-review-loop/loop-runs") -Filter "*loop-run.json" | Select-Object -First 1
    $runState = Get-Content -Raw -LiteralPath $run.FullName | ConvertFrom-Json
    $runState.continuation_required | Should -BeTrue
    $runState.should_send_to_gpt | Should -BeFalse
  }

  It "sends to GPT when next action explicitly requires external review" {
    $project = New-TestProject "external-decision"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "continue"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict CONTINUE -NextAction "send_evidence_to_gpt_pro"
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.should_send_to_gpt | Should -BeTrue
    $state.send_reason | Should -Be "next_action_requests_external_review"
    $state.local_only_next_action | Should -Be $null
  }

  It "blocks sensitive files but ignores generated loop ledger files" {
    $project = New-TestProject "scan"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    $reviewDir = Join-Path $project "docs/ai-review-loop/reviews"
    New-Item -ItemType Directory -Path $reviewDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $reviewDir "old-review.md") -Encoding UTF8 -Value "API_KEY=sk-abcdefghijklmnopqrstuvwxyz"
    & $script:Skill -Action Prepare -Root $project

    $state = Read-State $project
    $codeMapPath = Join-Path $project ($state.latest_code_map -replace "/", "\")
    (Get-Content -Raw -LiteralPath $codeMapPath) | Should -Not -Match "docs/ai-review-loop"

    Set-Content -LiteralPath (Join-Path $project ".env") -Encoding UTF8 -Value "API_KEY=sk-abcdefghijklmnopqrstuvwxyz"
    { & $script:Skill -Action Prepare -Root $project } | Should -Throw
  }

  It "documents Codex extension backend as the required browser route" {
    $skillText = Get-Content -Raw -LiteralPath (Join-Path $script:Root "SKILL.md")
    $browserFlow = Get-Content -Raw -LiteralPath (Join-Path $script:Root "references/chatgpt-browser-flow.md")

    $skillText | Should -Match "skill/instruction set"
    $skillText | Should -Match "Codex Edge/Chrome extension backend"
    $browserFlow | Should -Match "not necessarily a same-named callable tool"
    $browserFlow | Should -Match "Do not.*generic Playwright browser"
  }
}
