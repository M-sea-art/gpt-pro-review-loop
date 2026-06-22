BeforeAll {
  $script:Root = Resolve-Path (Join-Path $PSScriptRoot "..")
  $script:Skill = Join-Path $script:Root "scripts/gpt_pro_review_loop.ps1"
  $script:PreviousAuditorScript = $env:GPT_PRO_REVIEW_LOOP_AUDITOR_SCRIPT
  $env:GPT_PRO_REVIEW_LOOP_AUDITOR_SCRIPT = Join-Path $script:Root "tests/fixtures/fake_audit_codex_capabilities.py"

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

AfterAll {
  if ($null -eq $script:PreviousAuditorScript) {
    Remove-Item Env:\GPT_PRO_REVIEW_LOOP_AUDITOR_SCRIPT -ErrorAction SilentlyContinue
  } else {
    $env:GPT_PRO_REVIEW_LOOP_AUDITOR_SCRIPT = $script:PreviousAuditorScript
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
    $config.active_goal_scope | Should -Be "project_total"
    $config.terminal_goal_scope | Should -Be "project_total"
    $config.completion_guard_policy | Should -Be "project_total_only"
    $config.gpt_courtesy_footer | Should -Be "谢谢你的工作，GPT朋友。"
    $config.courtesy_footer_policy | Should -Be "after_first_external_review_in_continuous_loop"
    $config.pro_review_mode | Should -Be "optional"
    $config.efficiency_audit_mode | Should -Be "standard"
    $config.efficiency_audit_policy | Should -Be "capability_scan_goal_supervision_periodic_done_gate_final_closure"
    $config.loop_profile | Should -Be "conservative"
    $config.target_score | Should -Be 95
    $config.candidate_scope | Should -Be "test_line"
    $config.max_fixes_per_round | Should -Be 3
    $config.formal_completion_claim_allowed | Should -BeFalse
    $state.PSObject.Properties.Name | Should -Contain "pending_prompts"
    $state.PSObject.Properties.Name | Should -Contain "captured_reviews"
    $state.PSObject.Properties.Name | Should -Contain "runtime_brief"
    $state.PSObject.Properties.Name | Should -Contain "browser_preflight_status"
    $state.PSObject.Properties.Name | Should -Contain "browser_preflight_error_category"
    $state.PSObject.Properties.Name | Should -Contain "should_send_to_gpt"
    $state.PSObject.Properties.Name | Should -Contain "active_goal_scope"
    $state.PSObject.Properties.Name | Should -Contain "completion_guard_status"
    $state.PSObject.Properties.Name | Should -Contain "project_blocker_queue"
    $state.PSObject.Properties.Name | Should -Contain "current_blocker_id"
    $state.PSObject.Properties.Name | Should -Contain "stalled_local_action_count"
    $state.PSObject.Properties.Name | Should -Contain "latest_action_contract"
    $state.PSObject.Properties.Name | Should -Contain "latest_evidence"
    $state.PSObject.Properties.Name | Should -Contain "latest_evidence_id"
    $state.PSObject.Properties.Name | Should -Contain "action_executor_status"
    $state.PSObject.Properties.Name | Should -Contain "latest_evidence_strategy"
    $state.PSObject.Properties.Name | Should -Contain "latest_evidence_strategy_status"
    $state.PSObject.Properties.Name | Should -Contain "evidence_strategy_attempts"
    $state.PSObject.Properties.Name | Should -Contain "current_evidence_source"
    $state.PSObject.Properties.Name | Should -Contain "loop_profile"
    $state.PSObject.Properties.Name | Should -Contain "target_score"
    $state.PSObject.Properties.Name | Should -Contain "candidate_status"
    $state.PSObject.Properties.Name | Should -Contain "candidate_score"
    $state.PSObject.Properties.Name | Should -Contain "highest_deductions"
    $state.PSObject.Properties.Name | Should -Contain "testline_isolation_status"
    $state.PSObject.Properties.Name | Should -Contain "testline_git_metadata_kind"
    $state.PSObject.Properties.Name | Should -Contain "formal_completion_claim_allowed"
    $state.PSObject.Properties.Name | Should -Contain "latest_capability_scan"
    $state.PSObject.Properties.Name | Should -Contain "latest_efficiency_audit"
    $state.PSObject.Properties.Name | Should -Contain "latest_done_gate"
    $state.PSObject.Properties.Name | Should -Contain "latest_final_closure"
    $state.PSObject.Properties.Name | Should -Contain "recommended_capability_routes"
    $state.PSObject.Properties.Name | Should -Contain "stale_count"
    $state.PSObject.Properties.Name | Should -Contain "stall_pivot_status"
    $state.PSObject.Properties.Name | Should -Contain "done_gate_verdict"
    $state.PSObject.Properties.Name | Should -Contain "final_closure_verdict"
    $state.PSObject.Properties.Name | Should -Contain "latest_goal_contract"
    $state.PSObject.Properties.Name | Should -Contain "goal_contract_hash"
    $state.PSObject.Properties.Name | Should -Contain "goal_contract_confidence"
    $state.PSObject.Properties.Name | Should -Contain "goal_contract_status"
    $state.PSObject.Properties.Name | Should -Contain "goal_authority_sources"
    $state.PSObject.Properties.Name | Should -Contain "latest_architecture_map"
    $state.PSObject.Properties.Name | Should -Contain "experience_collection_policy"
    $state.PSObject.Properties.Name | Should -Contain "latest_experience_record"
    $state.PSObject.Properties.Name | Should -Contain "latest_auto_experience_key"
    $state.PSObject.Properties.Name | Should -Contain "auto_experience_count"
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
    $state.active_goal_scope | Should -Be "project_total"
    $state.terminal_goal_scope | Should -Be "project_total"
    $state.project_goal_verdict | Should -Be "CONTINUE"
    $state.completion_guard_status | Should -Be "not_evaluated"
    $state.goal_achieved_is_terminal | Should -BeFalse
    $state.gpt_courtesy_footer_sent_count | Should -Be 0
    $state.pro_review_mode | Should -Be "optional"
    $state.efficiency_audit_mode | Should -Be "standard"
    $state.stale_count | Should -Be 0
    $state.stall_pivot_status | Should -Be "CONTINUE"
    $state.evidence_strategy_attempts | Should -Be 0
    $state.loop_profile | Should -Be "conservative"
    $state.target_score | Should -Be 95
    $state.testline_isolation_status | Should -Be "not_required"
    $state.formal_line_protected | Should -BeTrue
    $state.formal_completion_claim_allowed | Should -BeFalse
    @($state.project_blocker_queue).Count | Should -Be 0
    $state.current_blocker_id | Should -Be $null
    $state.stalled_local_action_count | Should -Be 0
    @($state.action_contracts).Count | Should -Be 0
    @($state.evidence_records).Count | Should -Be 0
    $state.experience_collection_policy | Should -Be "key_events_only"
    $state.auto_experience_count | Should -Be 0
    Test-Path -LiteralPath (Join-Path $project "docs/ai-review-loop/loop-contract.json") | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $project "docs/ai-review-loop/loop-contract.md") | Should -BeTrue

    $statusText = (& $script:Skill -Action Status -Root $project | Out-String)
    $statusText | Should -Match "target_chatgpt_url"
    $statusText | Should -Match "https://chatgpt.com/g/test-project"
    $statusText | Should -Match "quota_mode"
    $statusText | Should -Match "efficiency_audit_mode"
    $statusText | Should -Match "auto_experience_count"
    $statusText | Should -Match "loop_profile"
    $statusText | Should -Match "target_score"
  }

  It "rejects invalid ChatGPT URLs at init" {
    $project = New-TestProject "bad-url"
    { & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://example.com/not-chatgpt" } | Should -Throw
  }

  It "records loop needs clarification as a formal contract gate" {
    $project = New-TestProject "clarify-loop-needs"
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action ClarifyLoopNeeds -Root $project

    $state = Read-State $project
    $contract = Get-Content -Raw -LiteralPath (Join-Path $project "docs/ai-review-loop/loop-contract.json") | ConvertFrom-Json
    $state.loop_status | Should -Be "paused"
    $state.goal_verdict | Should -Be "NEEDS_HUMAN_DECISION"
    $state.next_action | Should -Be "configure_loop_profile"
    $state.loop_contract_status | Should -Be "needs_user_choice"
    $contract.needs_user_choice | Should -BeTrue
    $contract.loop_profile | Should -Be "conservative"
  }

  It "blocks testline 95 auto mode until isolation is confirmed" {
    $project = New-TestProject "testline-no-git"
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action ConfigureLoopProfile -Root $project -LoopProfile testline_95_auto

    $state = Read-State $project
    $state.loop_profile | Should -Be "testline_95_auto"
    $state.loop_status | Should -Be "paused"
    $state.goal_verdict | Should -Be "NEEDS_HUMAN_DECISION"
    $state.candidate_status | Should -Be "CANDIDATE_BLOCKED"
    $state.testline_isolation_status | Should -Be "not_git_repo"
    $state.next_action | Should -Be "confirm_testline_isolation"
    $state.formal_completion_claim_allowed | Should -BeFalse
  }

  It "enters testline 95 auto mode only on a confirmed isolated branch" {
    $project = New-TestProject "testline-confirmed"
    git -C $project init -q
    git -C $project checkout -b codex/testline-confirmed | Out-Null
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action ConfigureLoopProfile -Root $project -LoopProfile testline_95_auto -ConfirmTestlineIsolation

    $state = Read-State $project
    $state.loop_profile | Should -Be "testline_95_auto"
    $state.testline_isolation_status | Should -Be "confirmed"
    $state.testline_branch_or_worktree | Should -Be "codex/testline-confirmed"
    $state.formal_line_protected | Should -BeTrue
    $state.formal_completion_claim_allowed | Should -BeFalse
  }

  It "recognizes linked Git worktrees as valid isolated test lines" {
    $main = New-TestProject "linked-main"
    git -C $main init -q
    git -C $main config user.email "test@example.com"
    git -C $main config user.name "Test User"
    git -C $main checkout -b codex/base | Out-Null
    git -C $main add README.md src/app.txt
    git -C $main commit -m "init" -q
    $linked = Join-Path (Split-Path $main -Parent) ("gpt-pro-review-loop-linked-{0}" -f [guid]::NewGuid().ToString("N"))
    git -C $main worktree add -q -b codex/testline-linked $linked

    & $script:Skill -Action Init -Root $linked
    & $script:Skill -Action ConfigureLoopProfile -Root $linked -LoopProfile testline_95_auto -ConfirmTestlineIsolation

    $state = Read-State $linked
    $state.testline_isolation_status | Should -Be "confirmed"
    $state.testline_branch_or_worktree | Should -Be "codex/testline-linked"
    $state.testline_git_metadata_kind | Should -Be "linked_worktree_file"
    $state.testline_git_probe_status | Should -Be "ok"
    $state.version_control_checked | Should -BeTrue
    $state.candidate_status | Should -Be "CANDIDATE_PARTIAL"
  }

  It "blocks testline 95 auto mode on formal Git branches" {
    $project = New-TestProject "testline-formal-branch"
    git -C $project init -q
    git -C $project checkout -b main | Out-Null
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action ConfigureLoopProfile -Root $project -LoopProfile testline_95_auto -ConfirmTestlineIsolation

    $state = Read-State $project
    $state.testline_isolation_status | Should -Be "formal_line_blocked"
    $state.loop_status | Should -Be "paused"
    $state.goal_verdict | Should -Be "NEEDS_HUMAN_DECISION"
    $state.candidate_status | Should -Be "CANDIDATE_BLOCKED"
    $state.next_action | Should -Be "confirm_testline_isolation"
  }

  It "recovers an old not_git_repo candidate block after a valid linked worktree is confirmed" {
    $main = New-TestProject "linked-recovery-main"
    git -C $main init -q
    git -C $main config user.email "test@example.com"
    git -C $main config user.name "Test User"
    git -C $main checkout -b codex/base | Out-Null
    git -C $main add README.md src/app.txt
    git -C $main commit -m "init" -q
    $linked = Join-Path (Split-Path $main -Parent) ("gpt-pro-review-loop-recovery-{0}" -f [guid]::NewGuid().ToString("N"))
    git -C $main worktree add -q -b codex/testline-recovery $linked
    & $script:Skill -Action Init -Root $linked

    $statePath = Join-Path $linked "docs/ai-review-loop/review-state.json"
    $state = Read-State $linked
    $state.loop_profile = "testline_95_auto"
    $state.loop_status = "paused"
    $state.goal_verdict = "NEEDS_HUMAN_DECISION"
    $state.candidate_status = "CANDIDATE_BLOCKED"
    $state.testline_isolation_status = "not_git_repo"
    $state.next_action = "confirm_testline_isolation"
    $state.local_only_next_action = "confirm_testline_isolation"
    $state.stop_reason = "Project is not inside a Git worktree."
    $state.send_reason = "testline_isolation_not_confirmed"
    $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding UTF8

    & $script:Skill -Action CheckTestlineIsolation -Root $linked -ConfirmTestlineIsolation

    $updated = Read-State $linked
    $updated.testline_isolation_status | Should -Be "confirmed"
    $updated.loop_status | Should -Be "running"
    $updated.goal_verdict | Should -Be "CONTINUE"
    $updated.candidate_status | Should -Be "CANDIDATE_PARTIAL"
    $updated.next_action | Should -Be "run_candidate_cycle"
    $updated.stop_reason | Should -Be $null
  }

  It "runs a candidate cycle below 95 without claiming project completion" {
    $project = New-TestProject "candidate-cycle"
    git -C $project init -q
    git -C $project checkout -b codex/testline-cycle | Out-Null
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nBuild a candidate.`n`nAcceptance gate: local candidate can run."
    & $script:Skill -Action Init -Root $project -LoopProfile testline_95_auto
    & $script:Skill -Action ConfigureLoopProfile -Root $project -LoopProfile testline_95_auto -ConfirmTestlineIsolation
    $output = (& $script:Skill -Action RunLoop -Root $project -ConfirmTestlineIsolation | Out-String)

    $state = Read-State $project
    $contract = Get-Content -Raw -LiteralPath (Join-Path $project "docs/ai-review-loop/loop-contract.json") | ConvertFrom-Json
    $expectedHeadings = @("【状态】", "【总分】", "【各项评分】", "【本轮实际改动】", "【运行/查看/使用方式】", "【证据】", "【最高扣分项】", "【下一轮自动目标】")
    @($contract.reporting_format) | Should -Be $expectedHeadings
    $actualHeadings = @($output -split "`r?`n" | Where-Object { $_ -match "^【.*】$" })
    $actualHeadings | Should -Be $expectedHeadings
    $output | Should -Match "【状态】"
    $output | Should -Match "【总分】"
    $output | Should -Match "【下一轮自动目标】"
    $state.loop_status | Should -Be "running"
    $state.candidate_status | Should -Be "CANDIDATE_PARTIAL"
    [int]$state.candidate_score | Should -BeLessThan 95
    $state.formal_completion_claim_allowed | Should -BeFalse
    $state.goal_achieved_is_terminal | Should -BeFalse
    $state.latest_candidate_fix_plan | Should -Match "^docs/ai-review-loop/loop-runs/"
    $state.local_only_next_action | Should -Not -BeNullOrEmpty
  }

  It "treats candidate pass as testline-only, not project-total completion" {
    $project = New-TestProject "candidate-pass-not-total"
    git -C $project init -q
    git -C $project checkout -b codex/testline-pass | Out-Null
    & $script:Skill -Action Init -Root $project -LoopProfile testline_95_auto
    & $script:Skill -Action ConfigureLoopProfile -Root $project -LoopProfile testline_95_auto -ConfirmTestlineIsolation
    $statePath = Join-Path $project "docs/ai-review-loop/review-state.json"
    $state = Read-State $project
    $state.candidate_score_breakdown = [pscustomobject]@{
      goal_fit = 25
      runnable_usability = 20
      result_quality = 20
      ux_readability = 15
      stability_correctness = 10
      delivery_completeness = 10
    }
    $state.project_blocker_queue = @()
    $state | ConvertTo-Json -Depth 20 | Set-Content -Encoding UTF8 -LiteralPath $statePath

    & $script:Skill -Action RecordCandidateScore -Root $project
    $updated = Read-State $project
    $updated.candidate_status | Should -Be "CANDIDATE_PASS"
    $updated.candidate_score | Should -Be 100
    $updated.loop_status | Should -Be "paused"
    $updated.project_goal_verdict | Should -Be "CONTINUE"
    $updated.goal_achieved_is_terminal | Should -BeFalse
    $updated.formal_completion_claim_allowed | Should -BeFalse
    $updated.stop_reason | Should -Be "candidate_pass_testline_only_not_project_total"
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

  It "continues locally instead of finaling when optional Pro URL is missing" {
    $project = New-TestProject "optional-pro-url-missing"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nShip without fake external review.`n`nAcceptance gate: verifier pass."
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action RunLoop -Root $project -ForceExternalReview

    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.continuation_required | Should -BeTrue
    $state.should_send_to_gpt | Should -BeFalse
    $state.latest_action_contract | Should -Match "^docs/ai-review-loop/action-contracts/"
    $state.latest_evidence | Should -Match "^docs/ai-review-loop/"
    $state.action_executor_status | Should -Be "executed"
    $state.next_action | Should -Not -Be "confirm_target_chatgpt_url"
    $state.local_only_next_action | Should -Not -Be "confirm_target_chatgpt_url"
    $state.url_confirmation_required | Should -BeTrue
    $state.auto_experience_count | Should -BeGreaterThan 0
    $experience = Get-Content -Raw -LiteralPath (Join-Path $project "docs/ai-review-loop/experience-log.md")
    $experience | Should -Match "pro_url_missing_local_loop"
    $experience | Should -Match "Missing optional GPT Pro URL"
    [int]$state.suppressed_experience_count | Should -BeGreaterThan 0
  }

  It "does not preserve confirm target URL as the local next action in optional RunLoop" {
    $project = New-TestProject "optional-runloop-no-url"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nContinue locally when Pro is optional.`n`nAcceptance gate: local verifier pass."
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action RunLoop -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.should_send_to_gpt | Should -BeFalse
    $state.latest_action_contract | Should -Match "^docs/ai-review-loop/action-contracts/"
    $state.latest_evidence | Should -Match "^docs/ai-review-loop/"
    $state.action_executor_status | Should -Be "executed"
    $state.next_action | Should -Not -Be "confirm_target_chatgpt_url"
    $state.local_only_next_action | Should -Not -Be "confirm_target_chatgpt_url"
    $state.next_action | Should -Not -Be "confirm_target_chatgpt_url"
    $state.raw_next_action | Should -Be "confirm_target_chatgpt_url"
    $state.next_action_normalization_reason | Should -Be "optional_pro_url_missing_local_loop"
  }

  It "recovers empty project queues from goal contract evidence instead of repeating local council" {
    $project = New-TestProject "empty-queue-contract"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nDeliver a governed local bridge without false completion.`n`nAcceptance gate: verifier pass.`nAcceptance gate: completion receipt evidence exists."
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action BuildGoalContract -Root $project
    & $script:Skill -Action RunDoneGate -Root $project

    $statePath = Join-Path $project "docs/ai-review-loop/review-state.json"
    $state = Read-State $project
    $state.project_blocker_queue = @()
    $state.blocking_gates = @()
    $state.goal_backlog = @()
    $state.current_goal_slice_id = $null
    $state.goal_slice_status = "no_open_slices"
    $state.next_action = "run_local_council"
    $state.local_only_next_action = "run_local_council"
    $state.done_gate_verdict = "NEEDS_FIX"
    $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding UTF8

    & $script:Skill -Action NextLocalAction -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.local_only_next_action | Should -Not -Be "run_local_council"
    @($state.project_blocker_queue).Count | Should -BeGreaterThan 0
    $state.send_reason | Should -Be "empty_queue_recovered_from_goal_contract"
  }

  It "local council creates a backlog item when recovery selects a non-council local action" {
    $project = New-TestProject "empty-queue-council-backlog"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nDeliver a governed local bridge without false completion.`n`nAcceptance gate: verifier pass."
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action BuildGoalContract -Root $project
    & $script:Skill -Action RunDoneGate -Root $project

    $statePath = Join-Path $project "docs/ai-review-loop/review-state.json"
    $state = Read-State $project
    $state.project_blocker_queue = @()
    $state.blocking_gates = @()
    $state.goal_backlog = @()
    $state.current_goal_slice_id = $null
    $state.goal_slice_status = "no_open_slices"
    $state.next_action = "run_local_council"
    $state.local_only_next_action = "run_local_council"
    $state.done_gate_verdict = "NEEDS_FIX"
    $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding UTF8

    & $script:Skill -Action RunLocalCouncil -Root $project

    $state = Read-State $project
    @($state.goal_backlog).Count | Should -BeGreaterThan 0
    $state.local_only_next_action | Should -Not -Be "run_local_council"
  }

  It "recommends local RunLoop continuation from Status when optional Pro URL is missing" {
    $project = New-TestProject "status-optional-pro-url-missing"
    & $script:Skill -Action Init -Root $project

    $statusText = (& $script:Skill -Action Status -Root $project | Out-String)

    $statusText | Should -Match "optional_pro_url_missing_continue_local_loop"
    $statusText | Should -Match "run_loop_local_without_pro"
    $statusText | Should -Match "next_action\s+: capture_or_run_local_review"
    $statusText | Should -Match "local_only_next_action\s+: capture_or_run_local_review"
    $statusText | Should -Match "raw_next_action\s+: confirm_target_chatgpt_url"
    $statusText | Should -Match "RunLoop"
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
    $prompt | Should -Match "Goal Context"
    $prompt | Should -Not -Match "谢谢你的工作，GPT朋友。"
    $state.quota_mode | Should -Be "economy"
    $state.last_prompt_chars | Should -Be $prompt.Length
    $state.cumulative_prompt_chars | Should -BeGreaterThan 0
    $state.runtime_brief | Should -Match "^docs/ai-review-loop/loop-runs/"
    $briefPath = Join-Path $project ($state.runtime_brief -replace "/", "\")
    $brief = Get-Content -Raw -LiteralPath $briefPath | ConvertFrom-Json
    $brief.latest_prompt | Should -Be $state.latest_prompt
    $brief.quota_mode | Should -Be "economy"
  }

  It "runs capability scan and keeps Game Studio as a recommended game route without upgrading exposure" {
    $project = New-TestProject "capability-scan"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RunCapabilityScan -Root $project -AuditContext "game Godot Phaser Three.js WebGL sprite playtest browser game prototype"

    $state = Read-State $project
    $state.latest_capability_scan | Should -Match "^docs/ai-review-loop/loop-runs/"
    $state.top_capability_family | Should -Be "game-studio"
    $state.top_capability_status | Should -Be "installed-not-exposed"
    @($state.recommended_capability_routes | Where-Object { $_ -match "game-studio" }).Count | Should -BeGreaterThan 0
    $scanPath = Join-Path $project ($state.latest_capability_scan -replace "/", "\")
    $scan = Get-Content -Raw -LiteralPath $scanPath | ConvertFrom-Json
    $scan.best_capabilities[0].name | Should -Be "game-studio"
    $scan.best_capabilities[0].status | Should -Be "installed-not-exposed"
    $scan.best_capabilities[0].directly_usable | Should -Be "not-until-exposed"
    $scan.best_capabilities[0].install_or_enable_needed | Should -Be "maybe-expose-or-enable"
    $scan.best_capabilities[0].authorization_needed | Should -Be "human-gate-before-write-or-external-action"
    $statusText = (& $script:Skill -Action Status -Root $project | Out-String)
    $statusText | Should -Match "recommended_capability_routes_preview"
    $statusText | Should -Match "game-studio"
  }

  It "RecordProgress triggers a periodic efficiency audit in standard mode" {
    $project = New-TestProject "progress-audit"
    $artifact = Join-Path $project "progress.md"
    Set-Content -LiteralPath $artifact -Encoding UTF8 -Value "# Progress"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RecordProgress -Root $project -ProgressArtifact $artifact -AuditContext "local development"

    $state = Read-State $project
    $state.latest_efficiency_audit | Should -Match "codex-efficiency-auditor-periodic-audit"
    $state.stall_pivot_status | Should -Be "CONTINUE"
    $reviewPath = Join-Path $project ($state.latest_efficiency_audit -replace "/", "\")
    (Get-Content -Raw -LiteralPath $reviewPath) | Should -Match "Codex Efficiency Audit"
    (Get-Content -Raw -LiteralPath $reviewPath) | Should -Match "periodic-audit"
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

  It "records browser runtime schema mismatch without marking prompt sent" {
    $project = New-TestProject "preflight-schema-mismatch"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action PreflightBrowser -Root $project -BrowserPreflightError "ConnectorClientError: missing field sandboxPolicy"

    $state = Read-State $project
    $state.browser_preflight_status | Should -Be "blocked_schema_mismatch"
    $state.browser_preflight_error_category | Should -Be "browser_runtime_schema_mismatch"
    $state.browser_preflight_error | Should -Match "sandboxPolicy"
    $state.baseline_sent | Should -BeFalse
    @($state.captured_reviews).Count | Should -Be 0
    $briefPath = Join-Path $project ($state.runtime_brief -replace "/", "\")
    (Get-Content -Raw -LiteralPath $briefPath) | Should -Match "blocked_schema_mismatch"
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

  It "keeps baseline hash stable when project content is unchanged" {
    $project = New-TestProject "stable-baseline"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action SendPrompt -Root $project -Send
    $sentState = Read-State $project
    $sentHash = $sentState.baseline_sent_hash

    Start-Sleep -Milliseconds 1100
    & $script:Skill -Action Prepare -Root $project

    $state = Read-State $project
    $state.baseline_hash | Should -Be $sentHash
    $promptPath = Join-Path $project ($state.latest_prompt -replace "/", "\")
    $prompt = Get-Content -Raw -LiteralPath $promptPath
    $prompt | Should -Match "Baseline already sent"
    $prompt | Should -Match "baseline code map already sent"
  }

  It "adds GPT courtesy footer only after the first external send" {
    $project = New-TestProject "courtesy"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    $state = Read-State $project
    $firstPromptPath = Join-Path $project ($state.latest_prompt -replace "/", "\")
    (Get-Content -Raw -LiteralPath $firstPromptPath) | Should -Not -Match "谢谢你的工作，GPT朋友。"

    & $script:Skill -Action SendPrompt -Root $project -Send
    & $script:Skill -Action Prepare -Root $project
    $state = Read-State $project
    $secondPromptPath = Join-Path $project ($state.latest_prompt -replace "/", "\")
    (Get-Content -Raw -LiteralPath $secondPromptPath) | Should -Match "谢谢你的工作，GPT朋友。"
    & $script:Skill -Action SendPrompt -Root $project -Send
    $state = Read-State $project
    $state.gpt_courtesy_footer_sent_count | Should -Be 1
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

  It "supports disabled Pro mode without target URL or prompt generation" {
    $project = New-TestProject "pro-disabled"
    & $script:Skill -Action Init -Root $project -ProReviewMode disabled
    & $script:Skill -Action Prepare -Root $project -ProReviewMode disabled

    $config = Read-Config $project
    $state = Read-State $project
    $config.pro_review_mode | Should -Be "disabled"
    $state.pro_review_mode | Should -Be "disabled"
    $state.url_confirmation_required | Should -BeFalse
    @($state.pending_prompts).Count | Should -Be 0
    $state.latest_prompt | Should -Be $null
    $state.should_send_to_gpt | Should -BeFalse
    $state.send_reason | Should -Be "pro_review_disabled"
  }

  It "requires GPT Pro evidence before terminal completion when Pro mode is required" {
    $project = New-TestProject "pro-required"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nShip the required-review project.`n`nAcceptance gate: verifier pass."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project" -ProReviewMode required
    & $script:Skill -Action RefreshProjectUnderstanding -Root $project
    $evidence = Join-Path $project "verifier-pass.txt"
    Set-Content -LiteralPath $evidence -Encoding UTF8 -Value "verifier pass"
    & $script:Skill -Action RecordProgress -Root $project -ProgressArtifact $evidence -RelatedGate "GATE-001" -EvidenceType "verification_command"
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "local terminal candidate"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "final_report"
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.goal_achieved_is_terminal | Should -BeFalse
    $state.project_goal_verdict | Should -Be "CONTINUE"
    $state.next_action | Should -Be "send_project_goal_completion_to_gpt_pro"
    $state.should_send_to_gpt | Should -BeTrue
    $state.send_reason | Should -Be "pro_review_required"
  }

  It "records auto close state for the target Pro tab" {
    $project = New-TestProject "close-tab"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action SendPrompt -Root $project -Send -OpenedTabUrl "https://chatgpt.com/g/test-project/c/abc123"
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "continue locally"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict CONTINUE -NextAction "collect_evidence"
    & $script:Skill -Action NextDecision -Root $project
    & $script:Skill -Action CloseProTab -Root $project

    $state = Read-State $project
    $state.pro_tab_close_policy | Should -Be "target_conversation"
    $state.pro_tab_close_status | Should -Be "closed"
    $state.pro_tab_close_target_url | Should -Be "https://chatgpt.com/g/test-project"
    $state.pro_tab_closed_at | Should -Not -Be $null
  }

  It "records a blocked close when no Pro tab is known" {
    $project = New-TestProject "close-tab-blocked"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action CloseProTab -Root $project

    $state = Read-State $project
    $state.pro_tab_close_status | Should -Be "blocked_no_target_tab"
  }

  It "runs a local expert council meeting with brainstorm before post-evaluation" {
    $project = New-TestProject "local-council"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value @"
Demo readiness: `NOT_READY`
Human Gate: manual visual signoff required
    Big World runtime: Not implemented
"@
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RunCapabilityScan -Root $project -AuditContext "game Godot browser playtest"
    & $script:Skill -Action BuildProjectGoalPlan -Root $project
    & $script:Skill -Action RunLocalCouncil -Root $project

    $state = Read-State $project
    $state.latest_local_council_review | Should -Match "^docs/ai-review-loop/reviews/"
    @($state.goal_backlog).Count | Should -BeGreaterThan 0
    @($state.goal_backlog | Where-Object { $_.status -eq "needs_human_decision" }).Count | Should -BeGreaterThan 0
    Test-Path -LiteralPath (Join-Path $project "docs/ai-review-loop/local-council.md") | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $project "docs/ai-review-loop/goal-backlog.md") | Should -BeTrue
    $reviewPath = Join-Path $project ($state.latest_local_council_review -replace "/", "\")
    $reviewText = Get-Content -Raw -LiteralPath $reviewPath
    $reviewText.IndexOf("## Brainstorm") | Should -BeLessThan $reviewText.IndexOf("## Post-Evaluation")
    $reviewText | Should -Match "鼓励自由发挥"
    $reviewText | Should -Match "暂停评判"
    $reviewText | Should -Match "数量优先"
    $reviewText | Should -Match "相互激发"
    $reviewText | Should -Match "记录所有的想法"
    $reviewText | Should -Match "后期评估"
    $reviewText | Should -Match "开放和包容"
    $reviewText | Should -Match "capability_route"
    (Get-Content -Raw -LiteralPath (Join-Path $project "docs/ai-review-loop/goal-backlog.md")) | Should -Match "Capability route"
  }

  It "records progress artifacts and generates a council review" {
    $project = New-TestProject "record-progress"
    $artifact = Join-Path $project "progress.md"
    Set-Content -LiteralPath $artifact -Encoding UTF8 -Value "# Progress"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RecordProgress -Root $project -ProgressArtifact $artifact

    $state = Read-State $project
    @($state.progress_artifacts).Count | Should -Be 1
    @($state.local_progress_artifacts).Count | Should -Be 1
    $state.latest_local_council_review | Should -Match "^docs/ai-review-loop/reviews/"
    $state.should_send_to_gpt | Should -BeFalse
  }

  It "promotes the first generated local goal without expanding human-gated scope" {
    $project = New-TestProject "promote-goal"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value 'Demo readiness: `NOT_READY`'
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action BuildProjectGoalPlan -Root $project
    & $script:Skill -Action RunLocalCouncil -Root $project
    & $script:Skill -Action PromoteGoal -Root $project

    $state = Read-State $project
    $state.active_generated_goal_id | Should -Match "^G-"
    $state.local_only_next_action | Should -Match "^collect_evidence_for_"
    $state.should_send_to_gpt | Should -BeFalse
  }

  It "adds GPT courtesy footer to assessment return after prior external send" {
    $project = New-TestProject "assessment-courtesy"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action SendPrompt -Root $project -Send
    & $script:Skill -Action CaptureReview -Root $project -Reviewer gpt-pro -Phase initial -ReviewText "review"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict CONTINUE -NextAction "collect_evidence"
    & $script:Skill -Action SendAssessment -Root $project

    $state = Read-State $project
    $assessmentPromptPath = Join-Path $project ($state.latest_assessment_prompt -replace "/", "\")
    (Get-Content -Raw -LiteralPath $assessmentPromptPath) | Should -Match "谢谢你的工作，GPT朋友。"
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

  It "keeps CaptureFeedback as a legacy alias for GPT Pro initial CaptureReview" {
    $project = New-TestProject "capture-feedback-alias"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action CaptureFeedback -Root $project -FeedbackText "legacy feedback"

    $state = Read-State $project
    @($state.captured_reviews).Count | Should -Be 1
    $reviewPath = Join-Path $project ($state.latest_review -replace "/", "\")
    $reviewText = Get-Content -Raw -LiteralPath $reviewPath
    $reviewText | Should -Match "reviewer: gpt-pro"
    $reviewText | Should -Match "phase: initial"
    $reviewText | Should -Match "legacy feedback"
  }

  It "maps terminal next decisions" {
    $project = New-TestProject "decision"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nShip the test project.`n`nAcceptance gate: verifier pass."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RefreshProjectUnderstanding -Root $project
    $evidence = Join-Path $project "verifier-pass.txt"
    Set-Content -LiteralPath $evidence -Encoding UTF8 -Value "verifier pass"
    & $script:Skill -Action RecordProgress -Root $project -ProgressArtifact $evidence -RelatedGate "GATE-001" -EvidenceType "verification_command"
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "done"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "final_report"
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "complete"
    $state.stop_reason | Should -Be "goal_achieved"
    $state.continuation_required | Should -BeFalse
    $state.completion_guard_status | Should -Be "project_goal_pass"
    $state.goal_achieved_is_terminal | Should -BeTrue
    $state.project_goal_verdict | Should -Be "GOAL_ACHIEVED"
    $state.done_gate_verdict | Should -Be "DONE_GATE_PASS"
    $state.final_closure_verdict | Should -Be "VERSION_CLOSED"
    $state.latest_done_gate | Should -Match "codex-efficiency-auditor-done-gate"
    $state.latest_final_closure | Should -Match "codex-efficiency-auditor-final-closure"
  }

  It "suppresses routine successful experience records but keeps important summaries" {
    $project = New-TestProject "auto-experience-suppression"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RunLocalCouncil -Root $project

    $state = Read-State $project
    $state.auto_experience_count | Should -Be 0
    [int]$state.suppressed_experience_count | Should -BeGreaterThan 0
    $experience = Get-Content -Raw -LiteralPath (Join-Path $project "docs/ai-review-loop/experience-log.md")
    $experience | Should -Not -Match "auto: local_council_captured"
    @(Get-ChildItem -LiteralPath (Join-Path $project "docs/ai-review-loop/experience-issues") -File -ErrorAction SilentlyContinue).Count | Should -Be 0
  }

  It "summarizes manual experience without creating redundant automatic entries" {
    $project = New-TestProject "experience-summary"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RecordExperience -Root $project -ExperienceOutcome "needs-improvement" -ExperienceLesson "Keep only behavior-changing review-loop lessons." -ExperienceNotes "Routine local council events should be suppressed."
    & $script:Skill -Action SummarizeExperience -Root $project

    $state = Read-State $project
    $state.latest_experience_summary | Should -Be "docs/ai-review-loop/experience-summary.md"
    $summary = Get-Content -Raw -LiteralPath (Join-Path $project "docs/ai-review-loop/experience-summary.md")
    $summary | Should -Match "total_log_entries: 1"
    $summary | Should -Match "needs-improvement"
    $summary | Should -Match "Keep-Worthy Recent Lessons"
    @(Get-ChildItem -LiteralPath (Join-Path $project "docs/ai-review-loop/experience-issues") -File -ErrorAction SilentlyContinue).Count | Should -Be 1
  }

  It "keeps subgoal achievement running instead of completing the total project" {
    $project = New-TestProject "subgoal"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nShip total project.`n`nAcceptance gate: verifier pass."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project" -GoalScope test_line
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "AUTOMATED_BETA_ACCEPTED"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "stop_after_final_report"
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.stop_reason | Should -Be $null
    $state.continuation_required | Should -BeTrue
    $state.completion_guard_status | Should -Be "subgoal_achieved_not_terminal"
    $state.goal_achieved_is_terminal | Should -BeFalse
    $state.subgoal_verdict | Should -Be "GOAL_ACHIEVED"
    $state.project_goal_verdict | Should -Be "CONTINUE"
    $state.next_action | Should -Be "assess_parent_project_goal"
    $state.should_send_to_gpt | Should -BeFalse
    $state.send_reason | Should -Be "local_only_continue"
    $state.local_only_next_action | Should -Be "assess_parent_project_goal"
  }

  It "blocks project-total completion when goal context still says not ready" {
    $project = New-TestProject "project-blocker"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value 'Demo readiness: `NOT_READY`'
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "done"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "final_report"
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.completion_guard_status | Should -Be "blocked_by_project_goal"
    $state.goal_achieved_is_terminal | Should -BeFalse
    @($state.blocking_gates).Count | Should -BeGreaterThan 0
    $state.next_action | Should -Be "collect_evidence_for_demo_readiness_not_ready"
    $state.should_send_to_gpt | Should -BeFalse
    $state.send_reason | Should -Be "local_only_continue"
    $state.local_only_next_action | Should -Be "collect_evidence_for_demo_readiness_not_ready"
    @($state.project_blocker_queue).Count | Should -BeGreaterThan 0
    $state.current_blocker_category | Should -Be "needs_evidence"
    Test-Path -LiteralPath (Join-Path $project "docs/ai-review-loop/project-goal-plan.md") | Should -BeTrue
  }

  It "Done Gate returns needs fix when project blockers remain" {
    $project = New-TestProject "done-gate-blocked"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value 'Demo readiness: `NOT_READY`'
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "done"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "final_report"
    & $script:Skill -Action RunDoneGate -Root $project

    $state = Read-State $project
    $state.done_gate_verdict | Should -Be "NEEDS_FIX"
    $state.latest_done_gate | Should -Match "codex-efficiency-auditor-done-gate"
  }

  It "Done Gate requires local evidence for explicit contract gates" {
    $project = New-TestProject "done-gate-missing-evidence"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nShip the governed project.`n`nAcceptance gate: verifier pass."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RefreshProjectUnderstanding -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "done"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "final_report"
    & $script:Skill -Action RunDoneGate -Root $project

    $state = Read-State $project
    $state.goal_contract_confidence | Should -Be "high"
    $state.done_gate_verdict | Should -Be "NEEDS_FIX"
    $doneGatePath = Join-Path $project ($state.latest_done_gate -replace "/", "\")
    (Get-Content -Raw -LiteralPath $doneGatePath) | Should -Match "Missing Contract Evidence"
    (Get-Content -Raw -LiteralPath $doneGatePath) | Should -Match "GATE-001"
  }

  It "binds RecordProgress evidence to a goal contract gate" {
    $project = New-TestProject "progress-evidence-binding"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nShip with evidence.`n`nAcceptance gate: verifier pass."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RefreshProjectUnderstanding -Root $project
    $artifact = Join-Path $project "verifier-pass.txt"
    Set-Content -LiteralPath $artifact -Encoding UTF8 -Value "PASS"
    & $script:Skill -Action RecordProgress -Root $project -ProgressArtifact $artifact -RelatedGate "GATE-001" -RelatedSliceId "GS-001" -EvidenceType "verification_command"

    $evidenceLog = Join-Path $project "docs/ai-review-loop/evidence/evidence.jsonl"
    $evidence = Get-Content -LiteralPath $evidenceLog | Select-Object -Last 1 | ConvertFrom-Json
    $evidence.related_gate | Should -Be "GATE-001"
    $evidence.related_slice_id | Should -Be "GS-001"
    $evidence.evidence_type | Should -Be "verification_command"

    & $script:Skill -Action BuildGoalContract -Root $project
    $contract = Get-Content -Raw -LiteralPath (Join-Path $project "docs/ai-review-loop/project-goal-contract.json") | ConvertFrom-Json
    @($contract.completion_gates | Where-Object { $_.id -eq "GATE-001" })[0].evidence_status | Should -Be "present"
  }

  It "migrates stale complete state back to running when project blockers exist" {
    $project = New-TestProject "stale-complete"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value "NOT_COMPLETE: V-P0-002 remains"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    $statePath = Join-Path $project "docs/ai-review-loop/review-state.json"
    $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
    $state.goal_verdict = "GOAL_ACHIEVED"
    $state.loop_status = "complete"
    $state.stop_reason = "goal_achieved"
    $state.goal_achieved_is_terminal = $false
    $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $statePath -Encoding UTF8

    & $script:Skill -Action Status -Root $project | Out-Null
    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.stop_reason | Should -Be $null
    $state.completion_guard_status | Should -Be "blocked_by_project_goal"
    $state.next_action | Should -Be "collect_evidence_for_not_complete_v_p0_002_remains"
    $state.should_send_to_gpt | Should -BeFalse
  }

  It "builds a categorized project blocker queue and goal plan" {
    $project = New-TestProject "blocker-queue"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value @"
# Roadmap

| Big World runtime | Not implemented |
| Demo readiness | `NOT_READY` |
| Remaining P0 Before Human Playtest | Manual visual acceptance |
| Remote Sync Path | separately authorized |
"@
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action BuildProjectGoalPlan -Root $project

    $state = Read-State $project
    @($state.project_blocker_queue).Count | Should -BeGreaterThan 0
    @($state.project_blocker_queue | Where-Object { $_.category -eq "explicit_authorization_required" }).Count | Should -BeGreaterThan 0
    @($state.project_blocker_queue | Where-Object { $_.category -eq "needs_evidence" }).Count | Should -BeGreaterThan 0
    @($state.project_blocker_queue | Where-Object { $_.category -eq "human_gate" }).Count | Should -BeGreaterThan 0
    Test-Path -LiteralPath (Join-Path $project "docs/ai-review-loop/project-goal-plan.md") | Should -BeTrue
    @(Get-ChildItem -LiteralPath (Join-Path $project "docs/ai-review-loop/loop-runs") -Filter "*project-goal-plan.json").Count | Should -BeGreaterThan 0
  }

  It "selects the next local action from the blocker queue" {
    $project = New-TestProject "next-local-action"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value 'Demo readiness: `NOT_READY`'
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action BuildProjectGoalPlan -Root $project
    & $script:Skill -Action NextLocalAction -Root $project

    $state = Read-State $project
    $state.local_only_next_action | Should -Be "collect_evidence_for_demo_readiness_not_ready"
    $state.should_send_to_gpt | Should -BeFalse
    $state.send_reason | Should -Be "local_only_continue"
  }

  It "executes a safe local action by writing an action contract and evidence record" {
    $project = New-TestProject "execute-local-action"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value 'Demo readiness: `NOT_READY`'
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action BuildProjectGoalPlan -Root $project
    & $script:Skill -Action NextLocalAction -Root $project
    & $script:Skill -Action ExecuteNextLocalAction -Root $project

    $state = Read-State $project
    $state.action_executor_status | Should -Be "executed"
    $state.latest_action_contract | Should -Match "^docs/ai-review-loop/action-contracts/"
    $state.latest_evidence | Should -Match "^docs/ai-review-loop/evidence/"
    $state.latest_evidence_id | Should -Match "^EV-"
    Test-Path -LiteralPath (Join-Path $project ($state.latest_action_contract -replace "/", "\")) | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $project ($state.latest_evidence -replace "/", "\")) | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $project "docs/ai-review-loop/evidence/evidence.jsonl") | Should -BeTrue
    @($state.local_progress_artifacts | Where-Object { $_ -eq $state.latest_evidence }).Count | Should -Be 1
    $state.continuation_required | Should -BeTrue
    $state.send_reason | Should -Be "local_action_executed"
  }

  It "prefers an open blocker over generic local review when executing a local action" {
    $project = New-TestProject "execute-prefers-blocker"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value 'AC-HMS-4: NOT_COMPLETE completion receipt evidence missing'
    Set-Content -LiteralPath (Join-Path $project "src/codex_bridge.py") -Encoding UTF8 -Value "def send_update():`n    return 'receipt'"
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action BuildProjectGoalPlan -Root $project
    $state = Read-State $project
    @($state.project_blocker_queue).Count | Should -BeGreaterThan 0
    $state.next_action = "capture_or_run_local_review"
    $state.local_only_next_action = "capture_or_run_local_review"
    $state | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath (Join-Path $project "docs/ai-review-loop/review-state.json") -Encoding UTF8

    & $script:Skill -Action ExecuteNextLocalAction -Root $project

    $state = Read-State $project
    $contractPath = Join-Path $project ($state.latest_action_contract -replace "/", "\")
    $contract = Get-Content -Raw -LiteralPath $contractPath | ConvertFrom-Json
    $contract.recommended_next_action | Should -Not -Be "capture_or_run_local_review"
    $contract.source_blocker_id | Should -Be "PB-001"
    $contract.executor | Should -Be "local-evidence-ledger"
  }

  It "creates gate-aware evidence strategy and binds evidence to the current blocker and gate" {
    $project = New-TestProject "gate-evidence-strategy"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/ACCEPTANCE.md") -Encoding UTF8 -Value 'AC-HMS-4: NOT_COMPLETE completion receipt delivery_status evidence missing'
    Set-Content -LiteralPath (Join-Path $project "src/codex_bridge.py") -Encoding UTF8 -Value "class DeliveryStatus:`n    pass`n"
    Set-Content -LiteralPath (Join-Path $project "src/run.py") -Encoding UTF8 -Value "def send_update():`n    delivery_status = 'unknown'`n"
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action RefreshProjectUnderstanding -Root $project
    & $script:Skill -Action BuildProjectGoalPlan -Root $project
    & $script:Skill -Action NextLocalAction -Root $project
    & $script:Skill -Action ExecuteNextLocalAction -Root $project

    $state = Read-State $project
    $state.latest_evidence_strategy | Should -Match "^docs/ai-review-loop/loop-runs/"
    $state.latest_evidence_strategy_status | Should -Be "executed"
    $state.evidence_strategy_attempts | Should -BeGreaterThan 0
    $state.current_evidence_source | Should -Not -BeNullOrEmpty
    $evidencePath = Join-Path $project ($state.latest_evidence -replace "/", "\")
    $evidenceText = Get-Content -Raw -LiteralPath $evidencePath
    $evidenceText | Should -Match "Gate-Aware Local Evidence"
    $evidenceText | Should -Match "codegraph_status"
    $records = Get-Content -LiteralPath (Join-Path $project "docs/ai-review-loop/evidence/evidence.jsonl") | ForEach-Object { $_ | ConvertFrom-Json }
    $last = @($records)[-1]
    $last.related_blocker_id | Should -Be "PB-001"
    $last.related_gate | Should -Match "^GATE-"
    $state.stale_count | Should -Be 0
    $state.stall_pivot_status | Should -Be "CONTINUE"
  }

  It "does not let a missing optional GPT URL override a concrete blocker action" {
    $project = New-TestProject "optional-url-keeps-blocker"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/ACCEPTANCE.md") -Encoding UTF8 -Value 'GATE-A: NOT_COMPLETE local verification evidence missing'
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action BuildProjectGoalPlan -Root $project
    & $script:Skill -Action RunLoop -Root $project

    $state = Read-State $project
    $state.raw_next_action | Should -BeIn @("confirm_target_chatgpt_url", $null)
    $state.latest_action_contract | Should -Match "^docs/ai-review-loop/action-contracts/"
    $contract = Get-Content -Raw -LiteralPath (Join-Path $project ($state.latest_action_contract -replace "/", "\")) | ConvertFrom-Json
    $contract.recommended_next_action | Should -Not -Be "capture_or_run_local_review"
    $contract.recommended_next_action | Should -Match "gate_001|not_complete|evidence"
    $state.latest_evidence_strategy_status | Should -Be "executed"
    $strategy = Get-Content -Raw -LiteralPath (Join-Path $project ($state.latest_evidence_strategy -replace "/", "\")) | ConvertFrom-Json
    $strategy.related_gate | Should -Match "^GATE-"
  }

  It "normalizes optional Pro URL confirmation before executing a local action" {
    $project = New-TestProject "execute-optional-url-confirm"
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action ExecuteNextLocalAction -Root $project

    $state = Read-State $project
    $contractPath = Join-Path $project ($state.latest_action_contract -replace "/", "\")
    $contract = Get-Content -Raw -LiteralPath $contractPath | ConvertFrom-Json
    $contract.recommended_next_action | Should -Be "capture_or_run_local_review"
    $contract.executor | Should -Be "local-council-ledger"
    $state.next_action | Should -Be "next_decision_after_local_action"
    $state.latest_evidence | Should -Not -Match "confirm_target_chatgpt_url"
    $state.send_reason | Should -Be "local_action_executed"
  }

  It "does not select no_project_blocker_queue_item as an executable local action" {
    $project = New-TestProject "next-local-action-empty-queue"
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action NextLocalAction -Root $project

    $state = Read-State $project
    $state.next_action | Should -Not -Be "run_local_council"
    $state.local_only_next_action | Should -Not -Be "run_local_council"
    $state.send_reason | Should -BeIn @("empty_queue_build_goal_slices", "empty_queue_rebuild_goal_plan", "empty_queue_recovered_from_goal_contract")
    $state.next_action | Should -Not -Be "no_project_blocker_queue_item"
  }

  It "writes the effective local-loop action into the project goal plan when optional Pro URL is missing" {
    $project = New-TestProject "goal-plan-optional-url-confirm"
    & $script:Skill -Action Init -Root $project
    & $script:Skill -Action BuildProjectGoalPlan -Root $project

    $state = Read-State $project
    $planPath = Join-Path $project "docs/ai-review-loop/project-goal-plan.md"
    $plan = Get-Content -Raw -LiteralPath $planPath
    $planJson = Get-ChildItem -LiteralPath (Join-Path $project "docs/ai-review-loop/loop-runs") -Filter "*project-goal-plan.json" | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $planState = Get-Content -Raw -LiteralPath $planJson.FullName | ConvertFrom-Json

    $state.next_action | Should -Be "capture_or_run_local_review"
    $state.local_only_next_action | Should -Be "capture_or_run_local_review"
    $state.send_reason | Should -Be "optional_pro_url_missing_local_loop"
    $plan | Should -Match "next_action: capture_or_run_local_review"
    $plan | Should -Match "local_only_next_action: capture_or_run_local_review"
    $plan | Should -Match "raw_next_action: confirm_target_chatgpt_url"
    $plan | Should -Match "normalization_reason: optional_pro_url_missing_local_loop"
    $planState.next_action | Should -Be "capture_or_run_local_review"
    $planState.raw_next_action | Should -Be "confirm_target_chatgpt_url"
  }

  It "pauses a local action contract that requires explicit human authorization" {
    $project = New-TestProject "execute-human-action"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nShip governed project.`n`nAcceptance gate: verifier pass."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "continue"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict CONTINUE -NextAction "push_release_to_github"
    & $script:Skill -Action NextDecision -Root $project
    & $script:Skill -Action ExecuteNextLocalAction -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "paused"
    $state.goal_verdict | Should -Be "NEEDS_HUMAN_DECISION"
    $state.action_executor_status | Should -Be "paused_human_decision"
    $state.stop_reason | Should -Be "action_requires_human_decision"
    $state.latest_action_contract | Should -Match "^docs/ai-review-loop/action-contracts/"
    @($state.evidence_records).Count | Should -Be 0
  }

  It "pauses when only human or explicit authorization blockers remain" {
    $project = New-TestProject "human-only"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value "Human Gate: manual visual signoff required"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "done"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "final_report"
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "paused"
    $state.goal_verdict | Should -Be "NEEDS_HUMAN_DECISION"
    $state.stop_reason | Should -Be "human_or_authorization_required"
    $state.next_action | Should -Be "request_human_decision_for_project_blockers"
    $state.should_send_to_gpt | Should -BeFalse
  }

  It "marks repeated local-only actions without artifacts as a process fix" {
    $project = New-TestProject "stalled-local"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/FPV0_COMPLETION_ROADMAP.md") -Encoding UTF8 -Value 'Demo readiness: `NOT_READY`'
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "done"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "final_report"
    & $script:Skill -Action NextDecision -Root $project
    & $script:Skill -Action NextDecision -Root $project
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.goal_verdict | Should -Be "NEEDS_PROCESS_FIX"
    $state.local_only_next_action | Should -Be "split_or_update_project_goal_plan"
    $state.stalled_local_action_count | Should -BeGreaterOrEqual 2
    $state.stale_count | Should -BeGreaterOrEqual 2
    $state.stall_pivot_status | Should -Be "REPEATED_FAILURE"
  }

  It "requires continuation when next decision is still running" {
    $project = New-TestProject "continue-decision"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nContinue governed project work.`n`nAcceptance gate: verifier pass."
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
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nReview governed project work.`n`nAcceptance gate: verifier pass."
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

  It "refreshes project understanding files for a new project" {
    $project = New-TestProject "understanding"
    New-Item -ItemType Directory -Path (Join-Path $project "docs") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Agents`n`nProject Identity`nBuild a small browser game prototype.`n`nVerification gate: npm test must pass."
    Set-Content -LiteralPath (Join-Path $project "package.json") -Encoding UTF8 -Value '{"scripts":{"test":"echo ok"}}'
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RefreshProjectUnderstanding -Root $project

    $base = Join-Path $project "docs/ai-review-loop"
    Test-Path -LiteralPath (Join-Path $base "project-goal-model.md") | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $base "project-goal-contract.json") | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $base "project-goal-contract.md") | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $base "project-architecture.md") | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $base "project-architecture-map.json") | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $base "architecture-brief.md") | Should -BeTrue
    Test-Path -LiteralPath (Join-Path $base "goal-slices.md") | Should -BeTrue

    $state = Read-State $project
    $state.latest_goal_model | Should -Be "docs/ai-review-loop/project-goal-model.md"
    $state.latest_goal_contract | Should -Be "docs/ai-review-loop/project-goal-contract.json"
    $state.goal_contract_hash | Should -Not -BeNullOrEmpty
    $state.goal_contract_confidence | Should -Be "high"
    $state.latest_architecture_snapshot | Should -Be "docs/ai-review-loop/project-architecture.md"
    $state.latest_architecture_map | Should -Be "docs/ai-review-loop/project-architecture-map.json"
    $state.latest_architecture_brief | Should -Be "docs/ai-review-loop/architecture-brief.md"
    $state.latest_goal_slices | Should -Be "docs/ai-review-loop/goal-slices.md"
    $state.project_total_goal | Should -Match "Agents|Test Project|Build"
  }

  It "keeps compressed architecture brief within the requested limit and includes required sections" {
    $project = New-TestProject "brief"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nA focused prototype.`n`nAcceptance gate: verifier pass.`nHuman Gate: required before release."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RefreshProjectUnderstanding -Root $project -ArchitectureBriefMaxChars 8000

    $briefPath = Join-Path $project "docs/ai-review-loop/architecture-brief.md"
    $brief = Get-Content -Raw -LiteralPath $briefPath
    $brief.Length | Should -BeLessOrEqual 8000
    $brief | Should -Match "## Goal"
    $brief | Should -Match "## Architecture"
    $brief | Should -Match "## Verification"
    $brief | Should -Match "## Risk"
    $brief | Should -Match "## Questions For GPT Pro"
  }

  It "writes a structured architecture map with scripts and protected paths" {
    $project = New-TestProject "architecture-map"
    New-Item -ItemType Directory -Path (Join-Path $project "game/autoload") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project`n`nProject Identity`nGodot project.`n`nAcceptance gate: godot tests pass."
    Set-Content -LiteralPath (Join-Path $project "project.godot") -Encoding UTF8 -Value "[autoload]`nRNGService=`"res://game/autoload/RNGService.gd`""
    Set-Content -LiteralPath (Join-Path $project "package.json") -Encoding UTF8 -Value '{"scripts":{"test":"node test.js","lint":"eslint ."}}'
    Set-Content -LiteralPath (Join-Path $project "game/autoload/RNGService.gd") -Encoding UTF8 -Value "extends Node"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action AnalyzeArchitecture -Root $project -ArchitectureAnalysisMode deep

    $map = Get-Content -Raw -LiteralPath (Join-Path $project "docs/ai-review-loop/project-architecture-map.json") | ConvertFrom-Json
    $map.project_type | Should -Be "Godot"
    @($map.package_scripts | Where-Object { $_ -match "test:" }).Count | Should -BeGreaterThan 0
    @($map.protected_paths | Where-Object { $_ -match "project.godot|game/autoload" }).Count | Should -BeGreaterThan 0
    $state = Read-State $project
    $state.latest_architecture_map | Should -Be "docs/ai-review-loop/project-architecture-map.json"
  }

  It "does not resend unchanged architecture brief after the first sent prompt" {
    $project = New-TestProject "brief-hash"
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action Prepare -Root $project
    $state = Read-State $project
    $firstPrompt = Join-Path $project ($state.latest_prompt -replace "/", "\")
    (Get-Content -Raw -LiteralPath $firstPrompt) | Should -Match "architecture_brief_mode: included"

    & $script:Skill -Action SendPrompt -Root $project -Send
    $sentState = Read-State $project
    $sentState.architecture_brief_sent_hash | Should -Be $sentState.architecture_brief_hash

    & $script:Skill -Action Prepare -Root $project
    $state2 = Read-State $project
    $secondPrompt = Join-Path $project ($state2.latest_prompt -replace "/", "\")
    $second = Get-Content -Raw -LiteralPath $secondPrompt
    $second | Should -Match "architecture_brief_mode: hash_only_unchanged"
    $second | Should -Match "Architecture brief unchanged"
  }

  It "pauses when project total goal confidence is low" {
    $project = New-TestProject "goal-conflict"
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Project A`nGOAL_CONFLICT: two incompatible total goals."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action RefreshProjectUnderstanding -Root $project

    $state = Read-State $project
    $state.goal_confidence | Should -Be "low"
    $state.loop_status | Should -Be "paused"
    $state.goal_verdict | Should -Be "NEEDS_HUMAN_DECISION"
    $state.next_action | Should -Be "clarify_project_total_goal"
  }

  It "builds an authority ordered goal contract" {
    $project = New-TestProject "goal-contract"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "AGENTS.md") -Encoding UTF8 -Value "# Agents`n`nProject Identity`nBuild governed project.`n`nDo not claim completion without Human Gate."
    Set-Content -LiteralPath (Join-Path $project "docs/project/ROADMAP.md") -Encoding UTF8 -Value "Acceptance gate: local verifier pass.`nRemaining P0: NOT_READY until evidence exists."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project"
    & $script:Skill -Action BuildGoalContract -Root $project

    $contractPath = Join-Path $project "docs/ai-review-loop/project-goal-contract.json"
    $contract = Get-Content -Raw -LiteralPath $contractPath | ConvertFrom-Json
    $contract.project_total_goal | Should -Match "Build governed project"
    @($contract.authority_sources)[0].path | Should -Be "AGENTS.md"
    @($contract.completion_gates).Count | Should -BeGreaterThan 0
    @($contract.non_completion_boundaries).Count | Should -BeGreaterThan 0
    $state = Read-State $project
    $state.goal_contract_status | Should -Be "active"
  }

  It "treats goal slice completion as non-terminal for project total" {
    $project = New-TestProject "slice-subgoal"
    New-Item -ItemType Directory -Path (Join-Path $project "docs/project") -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $project "docs/project/ROADMAP.md") -Encoding UTF8 -Value "Remaining P0: demo readiness NOT_READY."
    & $script:Skill -Action Init -Root $project -TargetChatGptUrl "https://chatgpt.com/g/test-project" -GoalScope test_line
    & $script:Skill -Action Prepare -Root $project
    & $script:Skill -Action CaptureReview -Root $project -Reviewer codex-efficiency-auditor -Phase goal-audit -ReviewText "test line accepted"
    & $script:Skill -Action AssessFeedback -Root $project -GoalVerdict GOAL_ACHIEVED -NextAction "slice_done"
    & $script:Skill -Action NextDecision -Root $project

    $state = Read-State $project
    $state.loop_status | Should -Be "running"
    $state.project_goal_verdict | Should -Be "CONTINUE"
    $state.goal_achieved_is_terminal | Should -BeFalse
    $state.latest_goal_slices | Should -Be "docs/ai-review-loop/goal-slices.md"
  }
}
