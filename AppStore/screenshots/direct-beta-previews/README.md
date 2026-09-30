# Direct-beta UI inspection — provisional, not Store screenshots

Inspected September 30, 2026, using CUA against the actual Release app at `.build/beta/DerivedData/Build/Products/Release/Face Hugger.app`. Its Info.plist reports **0.1.0 (1)**. The app was in dark appearance, with no account connected, no selected source, and no transfers. No account, runtime, or upload state was fabricated for these inspections.

## Inspected views

1. **Empty Transfer Bench:** two aligned native panes, gold direction marker, visible folder/account actions, disabled Upload action, and collapsed empty activity shelf. Text and headers were legible at the captured size; no visible clipping was found. The first capture was inactive, so toolbar controls appeared dimmed; a final asset must capture the active app.
2. **Filters popover:** native Include and Exclude fields, current `.DS_Store` exclusions, Cancel and Apply actions. The actual screenshot revealed that the `**/logs/**` example was interpreted as Markdown and displayed without its asterisks. The source now uses `Text(verbatim:)` and explicitly labels both filter fields for accessibility. Those changes require the next native build and recapture; the inspected binary predates them.

The app was restored to its empty workspace without applying any filters. No token entry, account connection, remote writes, appearance-setting changes, or uploads occurred.

## Export status

**No PNG files are present or claimed.** CUA rendered screenshots inline for visual inspection. Its documented screenshot API did not provide file export; a native screenshot attempt did not produce a saved asset, and launching the Screenshot utility timed out. Capture/export remains pending rather than being replaced with mock artwork.

The observations are limited to these two real views. They do not establish VoiceOver conformance, keyboard-only completion, light-mode quality, progress-state layout, Store-build behavior, or screenshot-dimension compliance. Use the [capture plan](../README.md) for the final sequence.
