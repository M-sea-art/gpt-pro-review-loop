# Experience Collection

The loop automatically records concise project-local experience after key review-loop state transitions. Use `RecordExperience` manually after a review round only when the result teaches something reusable enough to promote into a sanitized issue draft or cross-project improvement note.

Automatic records are written when the loop captures GPT Pro feedback, captures local council or efficiency review output, records progress, runs Done Gate, skips GPT because local work should continue, or writes a `NextDecision` loop-run record.

Command:

```powershell
& "$env:USERPROFILE\.codex\skills\gpt-pro-review-loop\scripts\gpt_pro_review_loop.ps1" -Action RecordExperience -Root "<project-root>" -ExperienceOutcome "success|blocked|needs-improvement" -ExperienceLesson "<short reusable lesson>" -ExperienceNotes "<sanitized notes>"
```

Local outputs:

- `docs/ai-review-loop/experience-log.md`: private project-local history.
- `docs/ai-review-loop/experience-issues/<timestamp>-github-issue-draft.md`: sanitized public issue draft.

Automatic records write only to `experience-log.md`. Manual `RecordExperience` writes to `experience-log.md` and creates an issue draft.

Record:

- What task or round was being reviewed.
- Whether the loop succeeded, blocked, or needs improvement.
- Whether GPT had enough baseline context.
- Whether Codex accepted, modified, rejected, or asked for more context on review recommendations.
- What should change in the skill, scripts, prompts, safety checks, or docs.
- Which prompt, review event, assessment event, and loop-run record provide evidence.

Do not record:

- API keys, cookies, browser session data, passwords, private account data.
- Large source snippets or proprietary business data.
- Full ChatGPT conversations when a short behavior summary is enough.

Promote a draft to a GitHub issue only if it would improve the reusable skill for future projects.
