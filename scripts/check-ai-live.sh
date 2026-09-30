#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
 Sources/ForgetIt/PlannerStore.swift Sources/ForgetIt/ReminderService.swift Sources/ForgetIt/Models.swift Sources/ForgetIt/LocalAIModels.swift Sources/ForgetIt/ClockDisplay.swift Sources/ForgetIt/WidgetSnapshot.swift Sources/ForgetIt/Scheduling.swift Sources/ForgetIt/Timetable.swift Sources/ForgetIt/TimetableCalendar.swift Sources/ForgetIt/DocumentInput.swift Sources/ForgetIt/AIConversation.swift \
 Sources/ForgetIt/LocalAIService.swift Sources/ForgetIt/AttachmentInput.swift Tests/LiveAI/InstructionCheck.swift \
 -o .build/ai-live-check
.build/ai-live-check
