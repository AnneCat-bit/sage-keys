"""Exercise Launch Services, including actual quit and re-launch, on the macOS runner."""
import json
import os
from pathlib import Path
import subprocess
import sys
import time

app, evidence, probe = map(Path, sys.argv[1:])
command = ["/usr/bin/open", "-W", "-n", "--stdout", str(evidence/"native-tests.log"),
           "--stderr", str(evidence/"native-stderr.log"), str(app), "--args", str(evidence), str(probe)]
with subprocess.Popen(command) as launch:
    pid_file = evidence/"qa-pid"
    deadline = time.monotonic() + 35
    while not pid_file.exists() and time.monotonic() < deadline and launch.poll() is None:
        time.sleep(0.1)
    if not pid_file.exists():
        raise RuntimeError("QA did not launch")
    host = pid_file.read_text().strip()
    with subprocess.Popen([sys.executable, "macos/Tests/processes.py", str(evidence), host]) as sampler:
        try:
            launch.wait(timeout=175)
        except subprocess.TimeoutExpired:
            subprocess.run(["/usr/bin/sample", host, "1", "5", "-file", str(evidence/"timeout-sample.txt")], timeout=10)
            print((evidence/"native-tests.log").read_text(), flush=True)
            try:
                os.kill(int(host), 15)
            except ProcessLookupError:
                pass
            raise
        sampler.wait(timeout=10)
print((evidence/"native-tests.log").read_text(), flush=True)
report = json.loads((evidence/"mac-results.json").read_text())
if report["failed"]:
    raise RuntimeError(report["failed"])

launches = []
for phase in ["quit-active", "restart-off"]:
    subprocess.run(command[:3] + [str(app), "--args", str(evidence), str(probe), phase], check=True, timeout=35)
    state = json.loads((evidence/(phase+".json")).read_text())
    try:
        os.kill(state["pid"], 0)
    except ProcessLookupError:
        launches.append(state)
    else:
        raise RuntimeError("Quit menu left process running")
assert launches[0]["pid"] != launches[1]["pid"]
assert launches[0]["activeAtQuit"] and not launches[1]["activeAtQuit"]
print("PASS quit and restart", launches)

guide_pids = set()
for phase in ["guide-draft", "guide-restored", "guide-mismatch", "guide-accessibility"]:
    with subprocess.Popen(command[:3] + [str(app), "--args", str(evidence), str(probe), phase]) as launch:
        if phase == "guide-accessibility":
            deadline = time.monotonic() + 28
            signal = evidence/"ax-ready"
            while not signal.exists() and launch.poll() is None and time.monotonic() < deadline:
                time.sleep(0.1)
            if signal.exists():
                ax_result = subprocess.check_output([evidence.parent/"guide-ax", signal.read_text()], timeout=10)
                temp = evidence/"ax.tmp"
                temp.write_bytes(ax_result)
                temp.replace(evidence/"guide-ax.json")
        launch.wait(timeout=55)
    if (evidence/(phase+".error")).exists():
        raise RuntimeError((evidence/(phase+".error")).read_text())
    result = json.loads((evidence/(phase+".json")).read_text())
    guide_pids.add(result["pid"])
    print("PASS", phase, result, flush=True)
assert len(guide_pids) == 4
