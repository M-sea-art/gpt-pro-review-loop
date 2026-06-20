# 安装 / 放置方式

## 方式 A：作为项目文档

推荐路径：

```text
docs/skills/新新手游戏开发顾问/SKILL.md
```

或：

```text
docs/process/NEWBIE_GAME_DEV_ADVISOR_SKILL.md
```

## 方式 B：作为 AI 助手上下文

在项目自定义指令或固定聊天窗口中加入：

```text
请遵循 docs/skills/新新手游戏开发顾问/SKILL.md。
用户是游戏开发完全新手，请以项目掌门视角提供建议。
```

## 方式 C：作为 Codex 参考文档

在 `AGENTS.md` 中加入：

```markdown
## Beginner Owner Advisor
When generating tasks, reports, or PR reviews for this project, also follow:
- docs/skills/新新手游戏开发顾问/SKILL.md

The owner is a complete beginner in game development.
Always explain what the human must judge, what Codex may do, and what must stop for Human Gate.
```

## 推荐目录

```text
project-root/
  AGENTS.md
  docs/
    skills/
      新新手游戏开发顾问/
        SKILL.md
```
