# Version 0.3.1 build 9 — final clock preference

- Added System default / 12-hour / 24-hour clock preference. Shared formatting covers deadlines, task/event lists, timetable axes/cards/details/import review, accessibility/help text, and rebuilt notification text. Time entry uses explicit hour/minute/AM-PM controls, independent of the macOS clock setting. Stored dates and AI/ICS wire formats are unchanged.
- Formatting tests passed for midnight, noon, afternoon minutes and both timetable-hour formats; the full existing regression suite passed.
- Preview UI verified selecting 12-hour in Preferences, AM/PM timetable axis and lesson labels, and task editor hour/minute/PM controls. Preview preferences are isolated from the real app.
- Release compilation, app signature and DMG checksum passed. Version remains 0.3.1, bundle build 9.
- Release-ready additions since v0.3.0 are listed in RELEASE_NOTES_v0.3.1.md. Desktop widgets remain excluded pending signing/integration validation.

# Version 0.3.1 build 8 — timetable calendar views

- Timetable opens on the current date in Day view. Import resets the selected date to today instead of selecting the earliest or next imported lesson.
- Added Day / Week / Month switching, Monday-first weekly/monthly grids, Today and previous/next navigation, lavender timed lesson blocks, separate scrollable all-day rows and a current-time line. Month dates and overflow counts open Day view. Lesson details show the full title, dates, location and notes.
- Layout regression tests pass for a short tutor period followed immediately by a lesson (both full-width), genuine overlaps, day/month bounds, all-day exclusion from time blocks, and midnight end boundaries. Existing scheduling, AI, clipboard and planner regression tests also passed.
- Isolated preview inspection verified today on initial entry, Day/Week/Month layouts, separate all-day assessment, readable lesson times/locations, visible current date at the end of Month view, date-to-Day navigation and Today returning from October 1 to September 30. Sample lessons exist only in memory-only preview mode; the saved planner was not edited.
- Release app built successfully, remains version 0.3.1 with bundle build 8. App signature and DMG checksum verified. Existing ad-hoc signing/widget release limitations remain unchanged.

# Version 0.3.1 build 7 — scheduling, imports and optional assistant

- Automated regression coverage: exact “set a task tomorrow reminding me to write a media essay”; relative-date ambiguity; local-day/DST arithmetic; removal of model-invented time; known-class/date question suppression; independent repeating occurrences and undo; weekdays excluding weekends; ICS unfolding, time zones, BYDAY/COUNT, EXDATE, rescheduling, durations and backup round trips; TXT/Markdown/CSV/RTF/DOCX/scanned-PDF input; model DELETE method, empty successful response and error response.
- Existing planner, event, ephemeral-chat, API cancellation/unload, clipboard and image-drop tests remain included.
- Preview UI: single calendar add menu provides New Task and New Event; repeat controls use the shared date picker; disabling Show study assistant removes AI settings and the toolbar assistant. Imported the synthetic fixture with 11 lessons after a cancelled date, inspected preview counts and the resulting weekly list. Preview data is memory-only.
- Earlier live qwen3.5:4b runs exercised explicit event dates, date corrections, unknown deadlines and the tomorrow request. They exposed both an invented 09:00 time and an intermittently empty event response. New date-only text requests now use All day; narrowly defined named events and date corrections use app-side handling. The final regression suite passes. The final integration run passed the app-side event/correction cases, then could not reach the configured installed model; a complete final live-model pass is not claimed. No model was downloaded or deleted from the owner's Mac.
- Widget source compiles with the macOS 26 SDK. Native gallery registration, actual wallpaper appearance, shared-container access and fresh-install operation are NOT verified: no configured Apple signing identity/team. The ordinary DMG intentionally excludes the extension. See Widgets/README.md for the remaining signed integration work.
- Release compilation passed; bundle version is 0.3.1, build 7. The app signature was verified.
- This remains an ad-hoc development build, not a notarized public release. The owner's actual timetable file and a clean machine have not been available for validation.

# Version 0.3.1 build 6 — AI correctness and ephemeral chat

- Regression tests pass for independent date/time parsing, seconds and AM/PM normalization, explicit date corrections, missing-date handling, and no premature “created” claims.
- Preview UI check: typed an unsent message, closed the assistant, and reopened it; the input and conversation were empty.
- Memory-only chat tests verify clearing input/messages/drafts and deleting the old saved-chat file on upgrade.
- Live checks used the installed qwen3.5:4b model with the actual app prompt and schema. Three final cases passed: an exact event instruction, a date/time correction, and a missing deadline requiring a question. The model omitted structured dates in the first two cases; deterministic explicit-date handling produced the correct review fields.
- Added Qwen3.5 9B from the official Ollama listing (6.6 GB). It was not downloaded or benchmarked; capability/performance bars are estimates.
- Existing planner, event, API cancellation/unloading, and clipboard tests pass.
- Final app signature and DMG checksum verified. Version remains 0.3.1, bundle build 6.

# Version 0.3.1 validation — 30 September 2026

- Existing 18 planner regression tests and local AI API/image tests pass.
- Added tests for one-chat disk persistence, unsent input and review-draft restoration, replacement without archives, multi-turn request context, context isolation and structured follow-up questions.
- Event tests cover no completion progress, no overdue status, calendar placement, date-based reminders, backup round trips and removal of work-plan fields when converting to an event.
- Inspected the isolated preview event editor: Event type, custom date button and time field, with no progress controls.
- Inspected sample chat question cards. Choosing English and using the answers populated the persistent message box and enabled Send.
- Opened the AI review calendar popover and chose 2 October; the date updated and the missing-date notice cleared.
- Closing and reopening the assistant retained its messages, unsent reply and chosen review date.
- Chat UI inspection used sample responses. Live local-model question quality remains unbenchmarked; no models were downloaded for this update.

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
