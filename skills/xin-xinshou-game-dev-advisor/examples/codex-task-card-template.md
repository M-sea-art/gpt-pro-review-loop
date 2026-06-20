# Codex Task: <任务名>

## Goal

本次改动要让什么变好？

## Context

相关文件：

- 

相关设计文档：

- 

当前限制：

- 

## Allowed Files

- 

## Forbidden Files

- `Main.tscn`
- `Main.gd`
- `project.godot`
- `.github/**`
- `game/autoload/**`
- Save / RNG / GameFlow / WorldState
- ContentDB
- action controller
- runtime route switching
- binary assets
- fonts unless license is explicit
- Steam / release files unless this is a release slice

## Scope

本次只做：

1. 
2. 
3. 

## Explicit Non-Goals

本次不做：

1. 
2. 
3. 

## Acceptance

必须满足：

- [ ] focused test pass
- [ ] relevant aggregate tests pass
- [ ] forbidden-path audit pass
- [ ] build report created
- [ ] screenshots if UI/visual work
- [ ] rollback instructions included

## Evidence

必须输出：

- changed files
- test logs
- screenshot path, if any
- export path, if any
- rollback command

## Rollback

```bash
git reset --hard <previous-sha>
```

或说明如何删除该 worktree / branch。

## Human Gate

遇到以下情况必须停：

- 需要改 Main / project.godot
- 需要新增图片或字体
- 视觉不确定
- 测试连续失败
- 需求范围变大
- 需要发布公开内容
