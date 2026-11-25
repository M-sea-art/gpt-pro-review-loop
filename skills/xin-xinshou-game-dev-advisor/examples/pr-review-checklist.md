# PR Review Checklist

## Verdict

- [ ] PASS
- [ ] PASS_WITH_NOTES
- [ ] NEEDS_FIX
- [ ] BLOCKED
- [ ] REJECT

## Scope

- [ ] PR 目标清楚。
- [ ] 改动与任务卡一致。
- [ ] 没有顺手扩大范围。

## Forbidden Path Audit

检查：

```bash
git diff --name-status origin/main...HEAD -- \
  .github \
  game/core \
  game/autoload \
  data \
  project.godot \
  export_presets.cfg \
  .gitignore \
  Main.tscn \
  Main.gd

git diff --name-status origin/main...HEAD -- '*.png' '*.jpg' '*.jpeg' '*.webp' '*.bmp' '*.tga'

git diff --name-status origin/main...HEAD -- '*.ttf' '*.otf' '*.woff' '*.woff2'

git diff --check
```

## Tests

- [ ] Focused tests passed.
- [ ] Relevant aggregate tests passed.
- [ ] Failure logs are included if anything failed.

## Evidence

- [ ] Build report exists.
- [ ] Screenshot artifact exists for visual work.
- [ ] Contact sheet exists for multi-screenshot review.
- [ ] Export path / hash exists for build work.

## Human Gate

- [ ] Visual work has human sign-off.
- [ ] Runtime work has explicit authorization.
- [ ] Asset / font work has license record.
- [ ] Release work has publication safety check.

## Merge Recommendation

```text
Do not merge / safe to merge after human approval / blocked pending fix
```

## Rollback

```bash
git revert <merge-commit>
```
