---
description: Pick up the next unfinished task from docs/IMPLEMENTATION.md and build it
argument-hint: "[optional task id, e.g. P2.4]"
---

You are continuing the UrbanMove build.

1. Read `CLAUDE.md`, `docs/PROGRESS.md`, and the relevant section of `docs/IMPLEMENTATION.md`.
2. Pick the task: if an ID was given (`$ARGUMENTS`), use that one; otherwise use the first unticked task in `docs/PROGRESS.md`.
   If it is a Phase 0 manual task, give Amruth exact step-by-step instructions instead of doing it.
3. Before writing code, reply with:
   - the task ID and goal in one line
   - a plan in 3–6 bullets
   - files you will create or change
   - any AWS resources it creates and their rough monthly cost (or "none")
   - open questions, if any (ask them and stop if they block the task)
4. Build it following the conventions in `CLAUDE.md`. Write tests alongside the code.
5. Run `make lint` and `make test`. For Terraform, run `fmt`, `validate`, and `plan`, and summarize the plan
   (add/change/destroy counts and notable resources). **Do not apply. Ask first.**
6. Run the task's **Verify** steps (after Amruth approves any apply) and report the actual output.
7. Update `docs/PROGRESS.md` (tick it, add a dated log line). Add an ADR to `docs/DECISIONS.md` if you made a design choice.
8. Propose a Conventional Commit message. Don't commit until asked.
