#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p .build
swiftc -Onone Source/main.swift Source/Shared.swift -o .build/StoreTests \
  -framework SwiftUI -framework AppKit -target arm64-apple-macosx14.0
.build/StoreTests --self-test
swiftc -Onone -parse-as-library Tests/WidgetTests.swift Source/Shared.swift Widget/ShixuWidget.swift \
  -D SHIXU_TESTING -target arm64-apple-macosx14.0 -o .build/WidgetTests
SHIXU_TEST_DATA="$ROOT/.build/widget-tests/tasks.json" .build/WidgetTests

bash Tests/InstallerTests.sh
