#!/bin/zsh
set -euo pipefail

SCRIPT_DIR="${0:A:h}"
RUN_ID="$(date +%Y%m%d-%H%M%S)"
EXPORT_ROOT="${EDGE_SOURCE_EXPORT_ROOT:-$SCRIPT_DIR/dist/source/$RUN_ID}"
REPOSITORY="$EXPORT_ROOT/spartan-build-program-macos"

if [[ -e "$EXPORT_ROOT" || "$EXPORT_ROOT" == "/" ]]; then
  print -u2 "เลือก Export root ใหม่เพื่อป้องกันการเขียนทับ: $EXPORT_ROOT"
  exit 2
fi

python3 - "$SCRIPT_DIR" "$REPOSITORY" <<'PY'
from pathlib import Path
import shutil
import sys

source, target = map(Path, sys.argv[1:])
files = [
    'EdgeProgrammer.swift', 'LocalBuild.swift', 'VHDLSupport.swift',
    'PinMappingSupport.swift', 'LogSupport.swift', 'BuildNotifications.swift',
    'SetupGuide.swift', 'Info.plist', 'edge-spartan7.json', 'AppIcon.png',
    'build_app.sh', 'prepare_repository.sh', 'README.md', 'README_TH.md',
    'INSTALL_MANUAL_TH.md', 'LICENSE', 'THIRD_PARTY_NOTICES.md', '.gitignore',
    'diagnostics/check_build_workflow.sh', 'diagnostics/fake_workflow_docker.py',
    'diagnostics/WorkflowHarness.swift',
    'diagnostics/portable_smoke.vhd', 'diagnostics/portable_smoke.xdc',
]
target.mkdir(parents=True, exist_ok=False)
for name in files:
    destination = target / name
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source / name, destination)
for name in ('docs', 'examples', '.github'):
    shutil.copytree(source / name, target / name,
                    ignore=shutil.ignore_patterns('.DS_Store', '__pycache__'))
PY

ditto -c -k --sequesterRsrc --keepParent "$REPOSITORY" "$EXPORT_ROOT/spartan-build-program-macos-source.zip"
(
  cd "$EXPORT_ROOT"
  shasum -a 256 spartan-build-program-macos-source.zip > SHA256SUMS.txt
)
print "REPOSITORY_PATH=$REPOSITORY"
print "SOURCE_ZIP_PATH=$EXPORT_ROOT/spartan-build-program-macos-source.zip"
