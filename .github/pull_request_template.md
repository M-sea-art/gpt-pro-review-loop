## What

Briefly describe the change.

## Why

Explain the user or maintenance problem this solves.

## Validation

- [ ] `python scripts/quick_validate.py .`
- [ ] PowerShell parser check
- [ ] `Invoke-Pester -CI`
- [ ] `git diff --check`
- [ ] Removed connector-path term guard passes in CI

## Safety

- [ ] No external direct project-access path added
- [ ] No public-network entry path added
- [ ] No generated project ledger committed
- [ ] Completion claims still require gates/evidence
