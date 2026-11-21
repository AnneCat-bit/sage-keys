"""Aggregate only the QA host and newly appearing WebKit services on a clean runner."""
import csv
import pathlib
import subprocess
import sys
import time

def processes():
    rows = subprocess.check_output(["ps","-ax","-o","pid=,rss=,time=,comm="],text=True)
    result = {}
    for row in rows.splitlines():
        fields=row.strip().split(None,3)
        if len(fields)!=4: continue
        pid,rss,cpu,command=fields
        if not pid.isdigit() or not rss.isdigit(): continue
        seconds=0.0
        for part in cpu.split(":"): seconds=seconds*60+float(part)
        result[int(pid)]=(int(rss),seconds,"com.apple.WebKit." in command)
    return result

root=pathlib.Path(sys.argv[1])
baseline=root/"existing-webkit-pids"
if len(sys.argv)==2:
    baseline.write_text(" ".join(str(p) for p,(_,_,wk) in processes().items() if wk))
    sys.exit()
host=int(sys.argv[2])
existing=set(map(int,baseline.read_text().split()))
previous=None
with (root/"process.csv").open("w") as output:
    writer=csv.writer(output)
    writer.writerow(["phase","interval_s","host_cpu_one_core_pct","host_rss_kib","new_webkit_cpu_one_core_pct","new_webkit_rss_kib","webkit_count"])
    while True:
        now=time.monotonic()
        phase=(root/"phase").read_text().strip() if (root/"phase").exists() else "setup"
        data=processes()
        if host not in data: break
        group={p for p,(_,_,wk) in data.items() if wk and p not in existing}
        if previous:
            then,last,prev_phase=previous
            if phase==prev_phase and phase in ("idle","typing15","typing30","trustedIdle","untrustedStandby"):
                elapsed=now-then
                def cost(pids):
                    return round(100*sum(max(0,data[p][1]-last[p][1]) for p in pids if p in last)/elapsed,2)
                writer.writerow([phase,round(elapsed,3),cost([host]),data[host][0],cost(group),sum(data[p][0] for p in group),len(group)])
                output.flush()
        previous=now,data,phase
        time.sleep(0.45)
