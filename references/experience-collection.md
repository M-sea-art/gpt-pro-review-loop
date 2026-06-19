# Experience Collection

Use `RecordExperience` after a review round when the result teaches something reusable about the skill, DevSpace connection, ChatGPT connector, browser automation, sensitive-data scanning, feedback quality, or out-of-bounds write detection.

Command:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RecordExperience -Root "<project-root>" -ExperienceOutcome "success|blocked|needs-improvement" -ExperienceLesson "<short reusable lesson>" -ExperienceNotes "<sanitized notes>"
```

Local outputs:

- `docs/ai-bridge/experience-log.md`: private project-local history.
- `docs/ai-bridge/experience-issues/<timestamp>-github-issue-draft.md`: sanitized public issue draft.

Record:

- What task or round was being reviewed.
- Whether the loop succeeded, blocked, or needs improvement.
- What failed or surprised the user.
- What should change in the skill, scripts, prompts, safety checks, or docs.
- Which local report and GPT feedback file provide evidence.

Do not record:

- API keys, owner tokens, OAuth callbacks, cookies, browser session data, passwords, private account data.
- Large source snippets or proprietary business data.
- Full ChatGPT conversations when a short behavior summary is enough.

Promote a draft to a GitHub issue only if it would improve the reusable skill for future projects.
