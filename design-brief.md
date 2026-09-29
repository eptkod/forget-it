# Study reminder app — design brief

**Status:** Working brief, updated 28 September 2026. This document describes the app to build; it is not an instruction to start building it yet.

## Purpose and scope

A personal, Mac-only study organiser for seeing coursework deadlines, planning when to work, and receiving useful reminders. It should feel like a real, native macOS app and remain comfortable to leave open all day on a 16 GB M2 MacBook. A `.dmg` will be the downloadable format if it is shared. A website may link to a GitHub Release containing that DMG. No phone, Windows, or web-app version is planned.

The app must be useful without AI or an internet connection. Manual entry, calendars, and reminders are the core. AI is an optional assistant for turning task details and images into calendar entries when the user explicitly invokes it; ambiguous details trigger questions before anything is added.

## Core experience

1. Create a class, such as **Math**, with a name, colour, and optional description. Each class has its own calendar or filtered view.
2. Add an assessment or study task. A task has a title, class, optional notes and attachments, a **real deadline**, an optional **work start date**, completion status, and reminder times. The data model should leave room for timed lesson events later, but a lesson timetable is not part of the initial feature set.
3. Open **All Calendars** to see everything together. Toggle individual classes on or off; selecting a class shows only its entries. Keep the same underlying items in both views, so edits and completion stay in sync.
4. In the main calendar, show multi-day work as **one continuous bar** across adjacent day columns. In plain terms, one long coloured strip stretches from the day the user starts working to the deadline, as in the owner's private Google Calendar reference. Separate, shorter items can occupy rows underneath. Treat this as a layout reference, not a request to copy Google's interface exactly. The personal reference screenshot stays out of the public repository.
5. The long bar makes the task visible on each day of its work span, but represents only **one task**, with one completion state. The **deadline** should be marked at the end and stay distinct from the intended work days. If the task is completed early, end or fade its active span on the completion day; if overdue and incomplete, keep it visibly overdue until completed. The bar itself does not trigger daily notifications.
6. Clicking a bar or event opens details for quick edits, completion, and reminder changes. Offer a fast **New Task** action, keyboard-friendly entry, and an obvious **Today / Upcoming / Overdue** view.

## Reminders

- Use macOS local notifications for the small corner pop-up, with the subject, task title, and deadline visible at a glance. Respect macOS notification permission and Focus settings; the system controls exact banner placement and presentation.
- Put the **default reminder schedule in Preferences** and allow a per-task override. On first setup, let the user choose a schedule rather than silently imposing one. Offer several clear options: at the deadline; one day before; several days before; once each day starting seven days before the deadline; and a custom schedule with chosen lead time, time of day, and frequency. A task can also have reminders turned off. Editing the due date or completing a task updates or cancels its pending notifications.
- Do not equate a calendar bar with a daily reminder. Avoid repeated or duplicate alerts unless the user explicitly chooses them.
- Tapping a notification should open the relevant task. Provide an in-app reminder settings screen and a clear indication when notification permission is off.
- In Preferences, make “once a day starting one week before” available as an obvious preset. If this preset is chosen, stop reminders when the task is completed; decide explicitly in the schedule whether alerts continue after the deadline. Avoid flooding Notification Center with old alerts.

Apple's [local notification documentation](https://developer.apple.com/documentation/usernotifications/scheduling-a-notification-locally-from-your-app) describes scheduling and cancellation even when the app is not active. Its [notification design guidance](https://developer.apple.com/design/human-interface-guidelines/notifications) calls for short, useful alerts and avoiding duplicates.

## Task assistant and image input

An optional **Add with AI** flow accepts pasted assignment text and pasted or attached screenshots, such as material copied from Google Classroom. It reads the source, identifies the main task, makes a concise task name and summary, extracts the actual due date/time, associates it with a class, and **adds it to that class's calendar**. If several distinct tasks are present, it should recognise them separately instead of merging them into one vague task. It may suggest a work start date, but must not invent an assessment requirement or deadline absent from the source.

If the class, due date, time, or main task is missing or ambiguous, ask a short, specific follow-up question before adding the task. For example: “Which class is this for?” or “Does ‘Friday’ mean 9 October?” Interpret dates using the user's locale and time zone. If the source is clear, create the task directly and show a brief success confirmation with **Edit** and **Undo**; do not require a full approval form for every import. Detect likely duplicates and ask before adding them. Retain the source text/image reference so the user can check what was read.

Here, “task summarizer” means summarising one supplied assignment or screenshot into a calendar task. A summary of the user's whole upcoming workload is a possible later feature, not part of this request.

### Local AI approach to investigate

- First extract printed text from images using Apple's on-device [Vision text recognition](https://developer.apple.com/documentation/vision/recognizing-text-in-images). Pass the extracted text to a small local model for task structuring. A vision-language model is useful when the image contains meaningful layout or non-text content that OCR loses.
- Use **Ollama** as the optional local runtime for the first implementation. Its [vision API](https://docs.ollama.com/capabilities/vision) accepts images, and its [structured outputs](https://docs.ollama.com/capabilities/structured-outputs) can request a task-shaped JSON response. Validate every field in app code; structured output does not guarantee the model interpreted the assignment correctly.
- Shortlist for a real test on the 16 GB M2 MacBook: [Qwen3-VL 2B](https://ollama.com/library/qwen3-vl/tags) (about 1.9 GB download), [Qwen3-VL 4B](https://ollama.com/library/qwen3-vl) (about 3.3 GB), and [Gemma 3 4B](https://ollama.com/library/gemma3) (about 3.3 GB). These are candidate download sizes, **not** measured RAM use or proof of extraction quality. Compare them on actual sample assignment text and images before choosing a default. The smaller 2B model is the first performance candidate; retain a 4B option if it is materially more accurate.
- Keep model choice replaceable. The model must load only for an explicit AI action, process one request at a time, and unload promptly afterward. Ollama supports `keep_alive: 0` to [unload after a response](https://docs.ollama.com/faq). Do not preload a model on app launch or keep it resident while the calendar sits open.
- The app DMG contains **no AI runtime or model**. On first use of Add with AI, check whether local Ollama is running and whether a suitable model is installed. If Ollama is absent, explain the extra installation and link to the [official Mac installer](https://docs.ollama.com/macos); after it starts, recheck from the app. If the model is absent, offer a recommended small model, show its approximate download size, and request the user's agreement before downloading it. Use Ollama's [model pull API](https://docs.ollama.com/api/pull) to show download progress. Do not silently install software or download gigabytes of model data.
- If Ollama is unavailable or setup is declined, manual task entry still works. The app communicates with Ollama through its [local HTTP API](https://docs.ollama.com/api/introduction); an MCP server is **not needed** to use other Ollama models. In an **Advanced > Local AI** setting, list already installed models via Ollama's [models API](https://docs.ollama.com/api/tags), let the user choose a compatible one or enter another model name, and allow a custom local Ollama endpoint for experienced users. Keep model downloads explicit. If a future integration truly needs MCP, design it separately rather than making it a dependency of the core app.
- Keep task details and images on device by default. Any future cloud AI would require a separate, explicit design decision.

### Performance expectations

The calendar and scheduled reminders must work without running AI inference. While idle, the app should have negligible CPU use and should not retain several gigabytes of model memory. There should be no continuous image scanning or periodic AI work. Test idle CPU, memory, battery impact, cold model load time, and one text and one image task on the owner's Mac before selecting a model. Prefer a shorter context and small input images when sufficient, while retaining readable source text.

## Interface direction

Native Mac layout: a resizable window with a sidebar for **All Calendars**, classes, and the task lists; a main month/week calendar; an optional detail inspector; and a restrained toolbar for Today, view switching, search, and New Task. Support light and dark appearance, keyboard shortcuts, readable text, and class colours that remain distinguishable without relying on colour alone.

Aim for a Liquid Glass feel using system components, not a blanket translucent calendar. Apple's [Liquid Glass adoption guide](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass) places the effect on navigation such as sidebars and toolbars and recommends split views with an inspector. Its [materials guidance](https://developer.apple.com/design/human-interface-guidelines/materials) says to use Liquid Glass sparingly for controls and navigation, while keeping the content layer legible with standard materials. Group related toolbar actions, allow the window to resize fluidly, and respect Reduce Transparency and Increase Contrast. [NavigationSplitView](https://developer.apple.com/documentation/swiftui/navigationsplitview) is a suitable SwiftUI starting point; the exact minimum macOS version remains to be chosen.

**Instruction for the implementing AI/developer:** Before implementing or finalising UI details, read the current Apple [Human Interface Guidelines for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/), [Adopting Liquid Glass](https://developer.apple.com/documentation/TechnologyOverviews/adopting-liquid-glass), [Materials](https://developer.apple.com/design/human-interface-guidelines/materials), and relevant SwiftUI/AppKit documentation. Confirm API availability for the chosen minimum macOS version. Use standard macOS behaviour for sidebars, toolbars, menus, notifications, accessibility, and appearance; do not assume a custom glass effect is always needed.

## Data, distribution, and first version

- Keep classes, tasks, events, completion dates, and reminder settings in local persistent storage. Ensure edits survive relaunch and the calendar can be used offline. Provide a simple backup/export path before storing a term's worth of work.
- Use the app's **own calendars**. Do not build Apple Calendar sync. Keep the calendar layout flexible enough to support timed lessons in a later version without making lesson scheduling a focus of the initial release.
- First useful version: class creation, All Calendars and class views, task entry, multi-day bars, completion, upcoming/overdue lists, and local notifications. Add the optional AI assistant after these work reliably.
- If sharing the app, package the Mac app in a DMG and upload it to a [GitHub Release](https://docs.github.com/en/repositories/releasing-projects-on-github/managing-releases-in-a-repository?tool=webui); link that release from the personal website. An unsigned, unnotarized hobby build may require the recipient to use macOS **Open Anyway**. Do not present that override as proof of safety. See [Apple's instructions](https://support.apple.com/en-am/guide/mac-help/open-a-mac-app-from-an-unknown-developer-mh40616/mac).

## Remaining decisions

1. Choose the minimum macOS version after checking UI API availability and the owner's current macOS version.
2. Benchmark the shortlisted local models on real task screenshots and pasted text before choosing the default offered in AI setup.
