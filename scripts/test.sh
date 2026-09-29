#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p .build/module-cache
swiftc -swift-version 5 -module-cache-path "$PWD/.build/module-cache" \
  Sources/ForgetIt/Models.swift Sources/ForgetIt/PlannerStore.swift Sources/ForgetIt/ReminderService.swift \
  Tests/ForgetItTests/PlannerTests.swift -o .build/planner-tests
.build/planner-tests
