# Provider codes residuals

Operator's call; none is a requirement until decided.

- R1 (verify, Opus N1, declined) Only one code field is registered for Escape. A hidden field whose commit was refused (invalid or duplicate) can absorb the first Escape, and a visible refused draft is dropped when the window closes. Neither draft could be saved.
- R2 (verify, Sol, declined; spec R3.6) Mixed-case keys passed directly to `providerGlyph(for:overrides:)`, `RingView.providerCodes` or `DropdownModel.providerCodes` are not matched; the app passes only validated lowercase maps.
- R3 (scope request, Opus) Show the default code next to the field, not only in the "Clear to restore" note.
- R4 The editing control, Escape, focus, commit on close and P44 have no view-inspection seam; they are checked by the release gate's UI pass, not by unit tests. The P41 header tests compare pixels; the redraw assertion is weak because an off-screen view always reports needing display.
- R5 Shrunk codes use the bold system font at the fitted size, not the pair-glyph font; only codes wider than the 13 pt area are affected.
