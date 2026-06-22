# Contributing

Thanks for improving `gpt-pro-review-loop`.

## Local Validation

Run these checks before opening a pull request:

```powershell
$env:PYTHONUTF8='1'
python scripts/quick_validate.py .

$path = "scripts/gpt_pro_review_loop.ps1"
$tokens = $null
$errors = $null
[System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $path), [ref]$tokens, [ref]$errors) | Out-Null
if ($errors.Count) { $errors | ForEach-Object { "$($_.Extent.StartLineNumber):$($_.Message)" }; exit 1 }

$env:GPT_PRO_REVIEW_LOOP_AUDITOR_SCRIPT = (Resolve-Path "tests/fixtures/fake_audit_codex_capabilities.py").Path
Invoke-Pester -CI

git diff --check
```

The GitHub Actions workflow runs the same core checks on Windows.

## Change Scope

- Prefer small, focused commits.
- Keep public actions backward-compatible unless the breaking change is explicit.
- Keep generated project ledgers out of this repository.
- Do not add direct local-project access for external reviewers.
- Do not add public-network or connector-server paths.

## Documentation

- Update `README.md` only for user-facing workflow changes.
- Update `SKILL.md` when Codex behavior or operator instructions change.
- Update `references/` for detailed protocol or browser-flow notes.
- Update `CHANGELOG.md` for every meaningful behavior change.

## Agents Manifest

`agents/openai.yaml` is a lightweight manifest for environments that surface skill cards or agent routing metadata. It is not required by the PowerShell script, but it documents the Chinese display name and default prompt used by OpenAI-style agent launchers.
