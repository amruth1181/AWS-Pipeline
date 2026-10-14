---
description: Review the current phase like a senior cloud engineer before moving on
argument-hint: "[phase number, defaults to current]"
---

Review phase `$ARGUMENTS` (or the current phase from `docs/PROGRESS.md`) critically. Check:

1. **Correctness:** does the code do what `docs/IMPLEMENTATION.md` says? Run the tests and the Verify steps again.
2. **Security:** IAM wildcards, missing encryption, public exposure, secrets in code or tfvars, missing TLS-only policies,
   overly broad SG rules. Run `checkov -d infra --quiet` and `tflint`.
3. **Cost:** any resource with an hourly charge that isn't behind a switch; log groups without retention.
4. **Reliability:** retries, DLQs, idempotency, timeouts, health checks.
5. **Code quality:** tests that matter (not just coverage), clear names, no dead code, handlers thin.
6. **Docs:** README, ADRs, and PROGRESS up to date.

Output a short list of findings ranked by severity, each with a concrete fix. Ask before fixing anything.
