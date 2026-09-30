# Native desktop widget (release integration pending)

The small and medium WidgetKit widgets show the current month and upcoming incomplete tasks/events from All Calendars. They read an atomic shared snapshot; they never run Ollama. Opening the widget opens All Calendars. The system controls refresh frequency, including refresh requests after planner edits.

The Swift source compiles against the macOS 26 SDK. It uses `containerBackground(for: .widget)`, `widgetAccentable`, and `widgetRenderingMode`, allowing macOS to supply its tinted/clear Liquid Glass appearance rather than drawing a fake glass background.

**Not included in the ad-hoc DMG.** A native widget with shared planner data needs an Apple signing team and valid shared app-group entitlement. This machine currently has Command Line Tools rather than full Xcode, and no discovered Developer ID signing identity. Compilation alone does not verify widget-gallery registration, sandbox data access, sizing or distribution.

When a Developer ID Application identity is available, run `scripts/build-widget-release.sh` with `FORGETIT_SIGNING_IDENTITY` and `FORGETIT_TEAM_ID` in the environment. This prepares an embedded extension, signs the extension and app with the same identity, and creates `dist/forget-it-widget.dmg`. The team-prefix app group follows Apple's macOS rules; no placeholder group or signing team is shipped. Apple Developer account configuration must match the bundle identifiers, and the script is not a substitute for archive/notarization validation in Xcode.

Before shipping: notarize/staple the signed app/DMG, install into Applications on a clean Mac, launch it, add each widget size through Edit Widgets, check calendar data after create/edit/complete/undo and relaunch, check empty state and accessibility, verify local midnight refresh, and check automatic/full-color/tinted/clear appearance against real wallpaper. The current development environment cannot complete these signed integration checks.

Apple references:
- https://developer.apple.com/documentation/widgetkit/creating-a-widget-extension
- https://developer.apple.com/documentation/widgetkit/optimizing-your-widget-for-accented-rendering-mode-and-liquid-glass
- https://developer.apple.com/documentation/xcode/accessing-app-group-containers
