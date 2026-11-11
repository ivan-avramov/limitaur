# Shared budget residuals

Operator's call; none is a requirement until decided.

- R1 Claude's reset day is configured, not reported. If Anthropic's real period differs, the bar's reset is wrong until the user changes the setting.
- R2 Reported Claude spend can lag by hours, so the combined total trails real spend.
- R3 Cursor's cycle comes from Cursor. A user whose Cursor cycle doesn't start on the configured day gets "Different billing period" and no combined bar.
- R4 (P37, declined) Just after the configured reset, a lagging provider could still report the previous month's spend. Limitaur cannot detect this.
- R5 (verify, Sol, declined) A hand-built `SharedBudgetState` with empty `memberSnapshots` still falls back to `wallNow` for the candidate time. No production path builds one.
- R6 (verify, Sol, declined) Amount pre-fill reads only the main row's reported limit and does not follow `aliasOf`. An alias-main Claude account leaves the amount empty when the budget is turned on.
- R7 H5 (budget card with no account rows) is checked by render only; there is no view-inspection seam.
- R8 With the budget on, its `SB` candidate takes a ranked menu-bar slot like any provider, so a lower-ranked provider bar can drop out at small indicator counts (P38: as designed).
