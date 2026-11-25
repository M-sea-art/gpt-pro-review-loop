# 新新手游戏开发顾问

**新新手游戏开发顾问**是一个面向游戏开发完全新手的 AI 辅助开发顾问 Skill。

它不是代码生成器，也不是自动发布机器人；它的目标是帮助项目所有者把 **Godot / Codex / GitHub / PR / CI / 截图证据 / 人工 Gate** 这些流程拆成能理解、能判断、能执行的小步骤。

## 适合谁

- 完全不懂游戏开发，但正在使用 ChatGPT / Codex 推进独立游戏项目的人。
- 想用 Godot + Codex 做 2D / 2.5D 独立游戏，但不想被工程术语淹没的人。
- 需要一个“项目掌门视角”的顾问：拆任务、控范围、审 PR、看风险、保留最终人类裁决。

## 核心原则

```text
新手不是程序员，新手是项目掌门。
Codex 可以做事，但不能默认 merge。
CI 绿不是视觉通过。
截图是证据，不是批准。
先做第一条可玩闭环，不先做大而全。
```

## 文件结构

```text
SKILL.md                                  主 Skill
README.md                                 仓库说明
LICENSE                                   MIT License
CHANGELOG.md                              更新记录
docs/USAGE.md                             使用方法
docs/INSTALL.md                           安装/放置方式
docs/GITHUB_PUBLICATION.md                GitHub 公开发布步骤
docs/PUBLICATION_SAFETY_CHECKLIST.md      公开发布前安全检查
examples/codex-task-card-template.md      Codex 任务卡模板
examples/newbie-project-triage.md         新手项目体检模板
examples/pr-review-checklist.md           PR 审查模板
prompts/daily-sync.md                     每日同步 prompt
prompts/project-triage.md                 项目体检 prompt
prompts/codex-task-card.md                任务卡生成 prompt
```

## 最短使用方式

把 `SKILL.md` 复制到你的项目技能库或 AI 助手上下文中，然后使用：

```text
启用「新新手游戏开发顾问」。
我是游戏开发新手，请用项目掌门视角帮我判断下一步。
```

## 推荐默认技术路线

| 领域 | 默认 |
|---|---|
| 引擎 | Godot 4.x |
| 语言 | GDScript first |
| 平台 | PC / Windows 优先 |
| AI 执行 | Codex |
| 高层规划 | ChatGPT |
| 版本管理 | Git + GitHub PR |
| 证据 | tests + screenshots + build reports + rollback |
| 决策 | Human Gate |

## License

MIT License. See [`LICENSE`](./LICENSE).
