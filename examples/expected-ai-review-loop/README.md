# Expected AI Review Loop Shape

An initialized project writes a local ledger under `docs/ai-review-loop/`.

Key expected properties:

- `project-config.json` includes transport, review memory, baseline, scan, code map, assessment, and return policies.
- `review-state.json` separates `pending_prompts`, compatibility `pending_reviews`, `captured_reviews`, and `pending_assessments`.
- Review and assessment filenames include timestamps so repeated captures do not overwrite earlier evidence.
- `docs/ai-review-loop/` is excluded from later project scans and code maps to avoid self-pollution.
