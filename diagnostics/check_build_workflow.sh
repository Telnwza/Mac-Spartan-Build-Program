#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
SOURCE_ROOT="${SCRIPT_DIR:h}"
TEST_ROOT="$(mktemp -d "${TMPDIR%/}/edge-workflow-XXXXXX")"
TEST_APP="$TEST_ROOT/WorkflowHarness.app"
mkdir -p "$TEST_APP/Contents/MacOS" "$TEST_APP/Contents/Resources" "$TEST_ROOT/cache"
export EDGE_WORKFLOW_TEST_ROOT="$TEST_ROOT"
export EDGE_WORKFLOW_SOURCE_ROOT="$SOURCE_ROOT"

python3 - "$SOURCE_ROOT" "$TEST_ROOT" <<'PY'
from pathlib import Path
import plistlib
import sys

source, target = map(Path, sys.argv[1:])
program = (source / 'EdgeProgrammer.swift').read_text()
(target / 'ProgrammerSupport.swift').write_text(program.split('@main\nstruct EdgeProgrammerApp:')[0])
info = {'CFBundleIdentifier': 'com.codex.edge-workflow-diagnostics',
        'CFBundleExecutable': 'WorkflowHarness', 'CFBundlePackageType': 'APPL'}
(target / 'WorkflowHarness.app/Contents/Info.plist').write_bytes(plistlib.dumps(info))
PY
cp "$SOURCE_ROOT/edge-spartan7.json" "$TEST_APP/Contents/Resources/edge-spartan7.json"
SWIFT_MODULECACHE_PATH="$TEST_ROOT/cache" \
CLANG_MODULE_CACHE_PATH="$TEST_ROOT/cache" \
xcrun --sdk macosx swiftc -parse-as-library -O -target "$(uname -m)-apple-macos13.0" \
    "$TEST_ROOT/ProgrammerSupport.swift" \
    "$SOURCE_ROOT/VHDLSupport.swift" \
    "$SOURCE_ROOT/PinMappingSupport.swift" \
    "$SOURCE_ROOT/LogSupport.swift" \
    "$SOURCE_ROOT/BuildNotifications.swift" \
    "$SOURCE_ROOT/LocalBuild.swift" \
    "$SOURCE_ROOT/SetupGuide.swift" \
    "$SCRIPT_DIR/WorkflowHarness.swift" \
    -o "$TEST_APP/Contents/MacOS/WorkflowHarness"
codesign --force --deep --sign - "$TEST_APP"

if [[ "${1:-fake}" == "live" ]]; then
    "$TEST_APP/Contents/MacOS/WorkflowHarness" live-cold
    "$TEST_APP/Contents/MacOS/WorkflowHarness" live-warm
else
    export EDGE_PROGRAMMER_DOCKER_PATH="$SCRIPT_DIR/fake_workflow_docker.py"
    export EDGE_WORKFLOW_BIT_FIXTURE="$TEST_ROOT/synthetic-header.bit"
    python3 - "$EDGE_WORKFLOW_BIT_FIXTURE" <<'PY'
from pathlib import Path
import sys

# Only exercises header recognition in the fake workflow; never program this file.
Path(sys.argv[1]).write_bytes(b'FAKE WORKFLOW ONLY: 7s15ftgb196 - NOT A REAL BITSTREAM\n')
PY
    "$TEST_APP/Contents/MacOS/WorkflowHarness" fake
fi
print "TEST_ROOT=$TEST_ROOT"
