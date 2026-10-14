# Getting started (Antigravity + Claude Code)

## 1. Put the files in place

1. Unzip this folder somewhere like `~/projects/urbanmove` (on Windows, inside WSL2, e.g. `/home/<you>/projects/urbanmove`).
2. `cd urbanmove && git init && git add . && git commit -m "docs: project plan and Claude Code context"`
3. Create an empty GitHub repo `amruth1181/AWS-Pipeline` (public), then
   `git remote add origin git@github.com:amruth1181/AWS-Pipeline.git && git push -u origin main`.

## 2. Open it in Antigravity

1. File → Open Folder → `urbanmove`.
2. Open the Claude Code panel (extension sidebar). Claude Code reads `CLAUDE.md` automatically from the folder root,
   and `.claude/settings.json` plus `.claude/commands/` give it the permissions and slash commands below.

## 3. Slash commands included

| Command | What it does |
|---|---|
| `/next` | Takes the next unticked task in `docs/PROGRESS.md`, plans, builds, tests, updates progress |
| `/next P2.4` | Works on a specific task |
| `/status` | Where the build stands, next step, current cost switches |
| `/review` | Senior-engineer review of the current phase before moving on |
| `/cost-check` | What's costing money right now and how to cut it |
| `/teardown` | Safely turns off hourly-cost resources |

## 4. First prompts to give Claude Code

1. `/status`, to check it understood the project.
2. `/next`. It starts with Phase 0 and walks you through the manual AWS setup (MFA, budget, CLI profile, tools).
3. `/next` again for P0.5 (bootstrap Terraform). It writes the code, shows the plan, and **you** approve the apply.
4. Keep going with `/next`. Run `/review` at the end of each phase.

## 5. Safety built in

- `terraform apply`, `git push`, and any other `aws` command → Claude must ask you first.
- `terraform destroy` and `make nuke` → blocked for Claude. Run them yourself if you ever need to.
- `.env`, AWS credentials, and Terraform state files → Claude can't read them.
- A $10/month budget alert (credits excluded) is created in P0.5. Do this before anything else in AWS.

## 6. Rhythm that works

About one phase per week. Get **Phase 2 (ingestion)** running early so history accumulates for the ML phase.
Run `make down` whenever you stop working on the API.
