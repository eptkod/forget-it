# forget it

A calm, native macOS homework planner. Version 0.3.1 targets **macOS 26 or later on Apple Silicon** and uses SwiftUI, AppKit, and UserNotifications. No third-party packages or account are required. Manual planning works offline; optional local AI uses Ollama.

![forget it app preview](assets/app-preview.png)

The source code is here; downloadable DMGs belong in [GitHub Releases](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository). See [PUBLISHING.md](PUBLISHING.md) for the first upload. The current DMG is a local development build, ad-hoc signed and not notarized.

## Run

For a source build, run `bash scripts/build-app.sh`, then open `dist/forget it.app`. On first launch, choose your default reminder schedule (including no reminders), then create a class and add tasks. Use ⌘N for a task, ⇧⌘N for a class, ⌘T to return the calendar to today, and ⌘, for Preferences.

Task dates are explicit calendar buttons. Browsing months never changes the value; selecting a day closes the picker.

The app is locally ad-hoc signed, not Developer ID signed or notarized. The DMG is a development build for local testing, not a public release.

## Build

Requires Swift 6.2 and the macOS 26 SDK (Xcode or Command Line Tools).

```sh
bash scripts/build-brand.sh  # Regenerate icons and downloadable artwork
bash scripts/build-app.sh
bash scripts/build-app.sh --dmg
bash scripts/test.sh
```

You can also open `Package.swift` in Xcode. Launch the packaged app to exercise notifications; the notification framework requires a valid app bundle. The test script compiles a standalone assertion runner so it also works with Command Line Tools without Xcode's test frameworks. Run the app with `--preview` for in-memory sample tasks; this mode never writes planner data or schedules notifications.

## Included

- Named, coloured classes with descriptions; edit a class using its context menu.
- All Calendars and individual class views, with class visibility toggles.
- Month/week calendar, continuous work-span bars, collision lanes, and deadline flags.
- Task editing, notes, local attachments, completion dates, all-day deadlines, and multi-part progress.
- Today, Upcoming, Overdue, Completed, and search views.
- Default and per-task reminders, including daily-from-one-week-before and custom lead time/time of day.
- Explicit choice to continue daily reminders for seven days after a deadline.
- Native local notifications; edits and completion replace/cancel pending alerts.
- Atomic local persistence, JSON backup/export, validated restore, and recovery copies before restore.
- Light/dark appearance, native navigation materials, keyboard entry, accessibility labels, and increased-contrast bar outlines.

## Homework, revision, and work days

Choose **Homework** for a task that finishes once, or enable **Split into parts** for several sessions. Each check completes one part; the whole calendar span disappears only after the final part. The task stays in Completed.

Choose **Revision** to track individual study days. Clicking a day within its calendar bar opens that particular study day. Completing it crosses out only that day; future days remain active. By default there is one session for every included day in the work span. An optional session target, such as three sessions, finishes the revision after that many distinct study days. Completed days remain visible; unused future days are removed. Each study day can count only once.

**Work days** offers Every Day, Weekdays Only, Weekends Only, and individual weekday toggles. Exclusions break the calendar bar and skip daily reminders; a real deadline on an excluded day is still shown with a dashed deadline entry. A fixed revision target cannot exceed the available days in the span.

**All day** hides the time field and treats the deadline as the end of the chosen day. Reminder presets expose a separate all-day reminder time. Timed deadlines keep their precise time.

Use the toolbar or footer **Undo** button to reverse recent planner changes, including accidental completion or deletion. Option-Command-Z also undoes a planner change; normal text-field undo is left to macOS. The current app session retains the last 20 planner changes. In the task editor, progress is a draft until Save Changes, and individual sessions have Undo buttons.

## Logo artwork

The folded-paper mascot is drawn from a shared vector source in `Sources/ForgetIt/BrandArtwork.swift`. The sidebar, task editor, onboarding, Preferences, app icon, and exported files use the same drawing. Running `bash scripts/build-brand.sh` creates `dist/forget-it-logo.zip` with a 2048-pixel app icon, a transparent mascot PNG, a vector PDF, and the ICNS file.

## Storage and reminders

Version 0.2 reads version 0.1 planners and saves version 2 data. Before the first update of a version 1 file, it keeps `planner-before-v0.2.json` beside the planner. Existing tasks default to Homework; change them to Revision where appropriate.

Data is stored at `~/Library/Application Support/ForgetIt/planner.json`. Attachments are embedded in backups; each file is limited to 20 MB. Backups are not encrypted. Use File → Export Backup regularly.

Reminder times follow the local calendar/time zone. One-day/three-day presets use the deadline's time of day. Daily/custom schedules use the selected reminder time and exclude times already passed. The earliest 60 upcoming alerts are queued; the queue refreshes when the app activates or data changes. Users with more than 60 scheduled alerts must periodically reopen the app. macOS permission and Focus determine delivery and presentation. No background AI or polling service runs.

## Scope and remaining work

Local AI speed, memory and accuracy have not yet been benchmarked against downloaded models on the owner’s Mac. Model-card ratings are estimates. Apple Calendar live sync is outside this version. School timetable imports are local snapshots, not subscriptions. Desktop widget source is included, but its signed integration and clean-install validation remain pending; see [Widgets/README.md](Widgets/README.md).

Before public distribution: exercise real notification delivery and opening a task from a banner, verify long-running behaviour and accessibility with the owner's settings, sign with Developer ID, notarize, and test the DMG on another Mac. No GitHub release is published by the build script.

## Design references

The implementation uses native system navigation and a legible content layer, following Apple's [macOS guidelines](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/), [Liquid Glass adoption guide](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass), and [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials). Notifications use Apple's [local notification APIs](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app).


## Optional local AI (0.3)

- **Assistant** in the toolbar imports tasks/events from text and attachments, or explains a selected task. Images, PDFs (including scanned pages), Word, RTF, TXT, Markdown and CSV are supported with explicit size/context limits. **Ask AI** is also available inside task details.
- Suggestions are editable and require review before saving. Missing dates/classes and possible duplicates are highlighted. Each import is one undoable planner change; original text and screenshots are retained.
- Launch checks Ollama availability and lists local models without loading a model. No installation or model download happens automatically.
- Cancellable onboarding installs the official Ollama Mac archive into `~/Applications/Ollama.app`, verifies it with macOS, and starts its bundled server. No Homebrew, Python, symlink or administrator password is required.
- Model cards offer **Qwen3.5 4B (~3.4 GB)**, **Qwen3.5 2B (~2.7 GB)** and **Qwen3-VL 2B (~1.9 GB)**. Download sizes and performance vary. Advanced settings support other local model names and a custom loopback server address.
- Requests run one at a time with `keep_alive: 0`; completion, failure and cancellation also trigger an unload request. The app does not preload models or run background inference. A server started by forget it stops when forget it quits; independently started Ollama servers are left running.
- Text and screenshots go only to the configured loopback endpoint. Remote endpoints, redirects and detected cloud models are rejected. Downloads contact Ollama’s official service. Clarification is read-only and receives the selected task’s context, not the entire planner.
- Task notes and AI input accept **⌘V**, image/file drag-and-drop, and the original file picker. Attachments remain part of planner backups.
- Use **Preferences → Local AI** to revisit setup or change models. Manual task entry remains available without AI.

### AI validation and limits

`bash scripts/test.sh` covers planner regression tests plus extraction validation, local endpoint restrictions, duplicate checks, backup preservation, simulated Ollama streams, interrupted/error responses, cancellation/unloading and a private image clipboard. Clipboard tests require normal macOS clipboard access.

The interface has been inspected in the isolated preview app. No multi-gigabyte model was downloaded during development. Actual model inference, cold-load time, memory use and a fresh Ollama installation still require real-device validation. The installer preserves an existing installation; cancellation leaves any completed installation and Ollama’s resumable partial model downloads in place.

Official references: [Mac installation](https://docs.ollama.com/macos), [chat API](https://docs.ollama.com/api/chat), [model downloads](https://docs.ollama.com/api/pull), [structured output](https://docs.ollama.com/capabilities/structured-outputs).


## What’s new in 0.3.1

- A dedicated, continuous assistant chat, with a message box that stays available during review.
- Follow-up question cards with suggested answers and free-text responses. Replies retain the current assignment’s context.
- Conversations are memory-only and clear when the assistant closes. Reopening starts fresh. The previous version’s saved chat file is removed on upgrade; there is no chat archive. Tasks explicitly added to the planner retain their source attachments.
- AI review uses the same explicit calendar popover as the task editor for deadlines and work start dates. Time selection remains separate.
- **New Event** adds presentations, appointments and other dated items with an optional time, notes, attachments and reminders. Events appear in the calendar and Today/Upcoming, retain their history, and have no completion checkbox or overdue status. The AI can suggest events too.


### v0.3.1 AI fixes (build 6)

- Date and time parsing are independent: an unexpected time format no longer replaces a valid date with today. Common forms such as `15:00:00`, `3pm` and `October 3rd, 2026` are normalized.
- A single fully specified date/time in the latest instruction overrides a stale one-item AI draft. Multiple-date requests stay with structured extraction and review.
- Missing dates show **Choose a date…** and cannot be approved until supplied. Review summaries come from the actual draft fields and never claim an item was created before saving.
- The latest user correction takes precedence over earlier suggestions.
- Added [Qwen3.5 9B](https://ollama.com/library/qwen3.5:9b), approximately 6.6 GB to download. It uses more memory and runs more slowly than the smaller choices; performance ratings remain estimates.
- Closing the assistant clears messages, screenshots, unsent input and review drafts. Cancelled responses cannot repopulate a closed chat.


## v0.3.1 build 7 additions

- One calendar-style **Add to Calendar** menu for both tasks and events; ⌘N still creates a task.
- **Preferences → Optional Features → Show study assistant** hides assistant controls and AI settings when switched off. Hidden assistants do not perform the launch model check.
- **Assistant → Models → Already on this Mac → Delete…** removes a downloaded model after confirmation. Ollama models are shared with other local apps; deleting one affects those apps too.
- Explicit relative dates such as today, tomorrow, day after tomorrow, weekdays and “in N days/weeks” are resolved using the local calendar for single-item requests. The exact “set a task tomorrow reminding me to…” form, clearly quoted titles with explicit dates, and simple single-item date corrections bypass model interpretation. New date-only text requests become all-day tasks instead of receiving an invented time. Complex requests still need review.
- **Timetable → Import Timetable…** previews a local `.ics` export before replacing the imported lessons. Timetable opens on today in Day view, with Day / Week / Month switching. Day and Week use lavender time blocks, a separate all-day row and a current-time line; Month shows a compact overview. Click a lesson for its full time, location and notes. Today returns to the current date, and importing never jumps back to the first historical lesson. Import/clear can be undone. Supported rules include daily/weekly/monthly/yearly frequency, intervals, counts/end dates, non-ordinal weekdays, month/day filters, exclusions, additional dates and individual reschedules/cancellations. Unsupported rules are reported, not silently treated as ordinary lessons. Open-ended imports have a two-year horizon shown in the preview; re-import to refresh. Your school's actual file has not yet been tested.
- **New Task/Event → Repeat** creates daily, weekday, weekly or monthly entries through the chosen end date (maximum 366). Each occurrence can be completed or edited separately. Repeats work without a timetable import; undoing creation removes the new series.
- Attachments can still be chosen, pasted or dropped. The assistant accepts up to six recent attachments and six images/scanned pages, rejects oversized content instead of silently truncating documents, and sends content only to the local model. Ordinary task attachments can use other file formats and open in their default Mac app.

The regular DMG remains a development build without a desktop widget. Native small/medium WidgetKit sources and a signing build script are in `Widgets/`; an Apple signing identity and signed integration checks are required before distributing that feature. System-managed tinted/clear rendering is used for the Liquid Glass appearance.

## Final v0.3.1 build

Choose **Preferences → Appearance → Clock format** for System default, 12-hour (AM/PM), or 24-hour time. This changes display and input controls without moving any deadlines or lessons. See [new features since v0.3.0](RELEASE_NOTES_v0.3.1.md) for release notes.
