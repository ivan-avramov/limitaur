# Cursor provider residuals

Operator's call; none is a requirement until decided.

- R1 A profile list saved with a Cursor profile cannot be decoded by 0.2.3 or earlier (downgrade unsupported).
- R2 The Cursor endpoints are private; a change surfaces as failed or unavailable.
- R3 Token renewal is not automatic; run `cursor-agent login`.
- R4 A Cursor 403 or 200 error envelope is unobserved; a 403 pauses like a 401.
- R5 Superseded by P25 (eligibility counts enabled profiles only).
- R6 The paused message for Cursor is the generic one.
- R7 A spend row whose day precedes the cycle start rejects the whole response; observed cycles and buckets both start at 00:00 UTC.
- R8 An invalid server cycle shows "Connection unavailable".
