# GitHub 公开仓库发布指南

## 1. 发布前原则

公开仓库只能包含：

```text
Skill 文本
通用模板
使用说明
公开安全检查表
```

不要包含：

```text
私有项目源码
私有仓库链接
API key / token / cookie
本地真实路径
未授权字体
未授权图片
AI 原始候选图
受版权保护的大段文本
商业计划、预算、账号、邮箱等敏感信息
```

## 2. 本地初始化

在本目录执行：

```bash
git init
git add .
git commit -m "Initial release: 新新手游戏开发顾问 skill"
```

## 3. 使用 GitHub CLI 创建公开仓库

把 `<owner>` 替换为你的 GitHub 用户名或组织名：

```bash
gh repo create <owner>/xin-xinshou-game-dev-advisor \
  --public \
  --description "A beginner-first AI game development advisor skill for Godot/Codex projects." \
  --source . \
  --remote origin \
  --push
```

## 4. 打标签

```bash
git tag v1.0.0
git push origin v1.0.0
```

## 5. 创建 GitHub Release

```bash
gh release create v1.0.0 \
  --title "新新手游戏开发顾问 v1.0.0" \
  --notes "Initial public release of the beginner-first AI game development advisor skill."
```

## 6. 发布后检查

```bash
gh repo view --web
```

检查：

- README 是否正常显示。
- SKILL.md 是否可读。
- 没有泄露私密内容。
- License 是否存在。
- Release 是否存在。
