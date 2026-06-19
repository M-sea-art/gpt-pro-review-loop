# Experience Collection

Use `RecordExperience` after a review round when the result teaches something reusable about the offline review loop, browser handoff, prompt quality, sensitive-data scanning, GPT feedback quality, or Codex local assessment quality.

Command:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RecordExperience -Root "<project-root>" -ExperienceOutcome "success|blocked|needs-improvement" -ExperienceLesson "<short reusable lesson>" -ExperienceNotes "<sanitized notes>"
```

Local outputs:

- `docs/ai-review-loop/experience-log.md`: private project-local history.
- `docs/ai-review-loop/experience-issues/<timestamp>-github-issue-draft.md`: sanitized public issue draft.

Record:

- What task or round was being reviewed.
- Whether the loop succeeded, blocked, or needs improvement.
- Whether GPT had enough baseline context.
- Whether Codex accepted, modified, rejected, or asked for more context on GPT recommendations.
- What should change in the skill, scripts, prompts, safety checks, or docs.
- Which prompt, GPT feedback file, and Codex assessment file provide evidence.

Do not record:

- API keys, cookies, browser session data, passwords, private account data.
- Large source snippets or proprietary business data.
- Full ChatGPT conversations when a short behavior summary is enough.

Promote a draft to a GitHub issue only if it would improve the reusable skill for future projects.
