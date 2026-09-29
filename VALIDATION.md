# Version 0.3 validation — 29 September 2026

- Release compilation and all 18 existing planner regression tests pass.
- Final 0.3.0 app signature verification and DMG checksum verification passed; dist/forget-it.dmg contains the updated build.
- Added automated checks for loopback-only endpoints, local model names, strict date parsing, extraction validation, mandatory review, missing source evidence, duplicate detection and original-source backup round trips.
- Simulated Ollama tests verify model filtering, streamed answers, interrupted/error responses, no inference during launch checks, keep_alive: 0, explicit unloading after success/failure/cancellation and disabled thinking for compatible models.
- A private macOS clipboard verifies image reading without altering the user's clipboard. Image data providers verify drag-and-drop decoding and image preparation.
- Inspected runtime setup and all three model cards in the isolated preview app. Verified Cancel returns to the planner and that normal text pasting enables Find Tasks in the assistant composer.
- Preview modes never install software, download models, perform inference or save planner changes.

Not yet tested with a downloaded model: actual inference quality, OCR/vision accuracy, cold-load time, RAM/battery use, partial-download resume behaviour or a clean Ollama installation. Ollama is already installed on this Mac; no model was silently downloaded for testing. Card ratings are estimates. Installer code uses the official Mac archive and macOS signature/Gatekeeper checks.

# Version 0.2 validation — 29 September 2026

- Release build succeeded with Swift 6.2.3 / macOS 26 SDK.
- 18 standalone planner tests pass with `bash scripts/test.sh`.
- Tests cover continuous calendar spans, cross-week collisions, per-day revision marks, distinct study-day counting, three-part homework, completion/reopening, excluded weekdays and deadline pins, all-day end-of-day semantics, all-day notification time, DST reminders, excluded-day reminder suppression, backup validation, legacy version 1 loading, adding parts to legacy completed work, and undo of progress/deletion.
- Inspected the running separate preview app. Its bundle ID now enforces in-memory sample data even if reopened without a launch argument.
- Clicked a specific day of a revision bar and confirmed the same day appeared in Task Details.
- Opened the explicit date button, navigated to the next month without changing selection, and selected a day. The popover closed and updated the date correctly.
- Completed that study day, saved, and verified it alone gained a completed mark while other days remained active. Toolbar Undo restored the original progress and bar.
- Verified the new mascot renders in the running app. Inspected the icon PNG and rasterized the exported vector PDF for visual inspection. Confirmed the logo ZIP includes PNG, transparent PNG, vector PDF and ICNS.
- The final app is ad-hoc signed and packaged as a development DMG. No public release was uploaded.

Existing version 1 data is decoded with Homework defaults and remains unchanged until edited. Before its first version 2 save, the app retains a recovery copy beside the planner. Completed homework is kept in Completed even though it no longer appears in the calendar.

Not verified end-to-end in this update: real notification banner delivery/click-through, VoiceOver navigation, long-running battery profiling, and Developer ID notarization. Notifications remain governed by macOS permissions and Focus. Optional AI import remains outside version 0.2.

Final package checks: `codesign --verify --deep --strict` passed, `hdiutil verify` reported a valid checksum, and the bundle version is 0.2.0. Reopened the finished app with the existing planner after confirming no task editor was open.
