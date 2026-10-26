#!/usr/bin/env python3
"""Deterministic Docker fixture for WorkflowHarness; never contacts Docker."""
import json
import os
from pathlib import Path
import re
import shutil
import sys
import time

root = Path(os.environ["EDGE_WORKFLOW_TEST_ROOT"])
control = json.loads((root / "control.json").read_text())
args = sys.argv[1:]
with (root / "commands.jsonl").open("a") as log:
    log.write(json.dumps(args) + "\n")

if args[0] == "info":
    time.sleep(control.get("info_delay", 0))
    if control.get("engine_down"):
        print("Docker Engine unavailable", file=sys.stderr)
        sys.exit(1)
    print("ENGINE_ID=" + control.get("engine", "engine-1"))
elif args[:2] == ["image", "inspect"]:
    if control.get("missing_image"):
        sys.exit(1)
    print("IMAGE=" + control.get("platform", "linux/amd64") + " "
          + control.get("image", "sha256:image-1"))
elif args[0] == "run" and "LOCAL_ENV_PASS" in args[-1]:
    if control.get("probe_failure"):
        sys.exit(2)
    print("LOCAL_ENV_PASS")
elif args[0] == "run":
    if control.get("build_failure"):
        print("ERROR: VHDL fixture failure")
        sys.exit(1)
    mounts = [args[i + 1] for i, value in enumerate(args[:-1]) if value == "-v"]
    source = Path(next(value[:-8] for value in mounts if value.endswith(":/src:ro")))
    result = Path(next(value[:-9] for value in mounts if value.endswith(":/work:rw")))
    top = re.search(r"^set top (\w+)$", (source / "build.tcl").read_text(), re.M)[1]
    shutil.copyfile(os.environ["EDGE_WORKFLOW_BIT_FIXTURE"], result / (top + ".bit"))
    timing = "Timing failed" if control.get("timing_failure") else "All user specified timing constraints are met"
    (result / "timing_summary.rpt").write_text(timing)
    errors = 1 if control.get("route_failure") else 0
    (result / "route_status.rpt").write_text(f"# of nets with routing errors.......... : {errors} :")
    print("BUILD_COMPLETE: /work/" + top + ".bit")
else:
    print("Unexpected fixture arguments", file=sys.stderr)
    sys.exit(2)
