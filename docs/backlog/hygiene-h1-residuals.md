# Hygiene H1 residuals

Operator's call; none is a requirement until decided.

- R-H1 (change review 2, opus, minor): the frozen `InstanceLockTests.acquisitionAndPermissions` re-acquire retries `held` for up to one second after one unexplained failure in about 40 full-suite runs (output not captured beyond the assertion line). Its comment blames a concurrently spawned child; that is unproven and probably wrong (the descriptor is close-on-exec and every spawn is `posix_spawn`). Fix: correct the comment through the test-writer; log any retried `held` with `lsof` on the lock file so a recurrence leaves evidence. Budget about 10 test lines.
- R-C11 second half (unchanged): the live `AppController.init` wiring of `nudger:` and `attemptStore:` is not exercised.
- P353 remainder (unchanged): counter-epoch cases after sleep/wake or a merge-cancelled request.
- Specification residuals: two users on one Mac each get an instance (intended); a relaunch within about five seconds of quitting can exit 3 while the quitting process waits for a nudge; a Finder or `open -n` second launch exits 3 silently; after a resume within the original retention window the retained snapshot can show again until that window ends; an unavailable lock runs unguarded.
- Budgets: product 47 changed lines (budget 50), documentation 12 (30), tests about 288 lines against 150, accepted by the operator (P555.1).
