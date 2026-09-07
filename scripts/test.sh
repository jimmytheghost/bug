#!/bin/sh
set -eu
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
PROJECT_ROOT=$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd)
FRAMEWORKS=/Library/Developer/CommandLineTools/Library/Developer/Frameworks
LIBRARIES=/Library/Developer/CommandLineTools/Library/Developer/usr/lib
# SwiftPM's generated runner must also see Testing.framework with standalone CLT.
# Target-only framework flags can compile tests but silently execute zero of them.
if [ -d "$FRAMEWORKS/Testing.framework" ]; then
    swift test --package-path "$PROJECT_ROOT" --enable-swift-testing \
        -Xswiftc -F -Xswiftc "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
        -Xlinker -rpath -Xlinker "$LIBRARIES" "$@"
else
    swift test --package-path "$PROJECT_ROOT" --enable-swift-testing "$@"
fi
