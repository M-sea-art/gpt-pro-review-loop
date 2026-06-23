# Benchmarks

This folder records lightweight, reproducible checks for the public value of the loop.

The first benchmark target is surface compression:

- default local loop does not require a ChatGPT URL;
- GPT Pro prompt generation happens only after explicit opt-in;
- project-total completion remains guarded by local evidence;
- public command surface is short enough for routine use;
- old direct-connector/public-entry wording stays removed.

Run:

```powershell
python scripts/surface_check.py .
```

