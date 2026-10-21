import time
from conftest import run


def env(tmp_path, proc, **kw):
    hook = tmp_path / "hook.sh"
    if not hook.exists():
        hook.write_text(f'#!/usr/bin/env bash\nprintf "%s|%s\\n" "$1" "$2" >> {tmp_path}/notified\n')
        hook.chmod(0o755)
    e = {"OOMG_PROC_ROOT": str(proc.base), "OOMG_ONCE": "1", "OOMG_STATE_DIR": str(tmp_path / "state"),
         "OOMG_NOTIFY": str(hook), "OOMG_PRIO_SCRIPT": "", "OOMG_THRESH_MB": "2048"}
    e.update(kw)
    return e


def notified(tmp_path):
    f = tmp_path / "notified"
    return f.read_text().splitlines() if f.exists() else []


def test_above_threshold_no_alert(tmp_path, proc):
    proc.meminfo(4_000_000)
    r = run("mem_watch.sh", env(tmp_path, proc))
    assert "MemAvailable=3906MB" in r.stdout and "ALERT" not in r.stdout
    assert notified(tmp_path) == []


def test_below_threshold_alerts_with_top_rss(tmp_path, proc):
    proc.meminfo(1_000_000, 512_000)
    proc.add(10, 1, "chrome", ["chrome"], rss_kb=900_000)
    proc.add(11, 1, "node", ["node"], rss_kb=300_000)
    r = run("mem_watch.sh", env(tmp_path, proc))
    assert "ALERT sent" in r.stdout
    (msg,) = notified(tmp_path)
    assert msg.startswith("Memory low: 976MB available|")
    assert "SwapFree 500MB" in msg and "chrome(878MB)" in msg
    assert msg.index("chrome(") < msg.index("node(")


def test_dedupe_within_window(tmp_path, proc):
    proc.meminfo(1_000_000)
    run("mem_watch.sh", env(tmp_path, proc))
    r = run("mem_watch.sh", env(tmp_path, proc))
    assert "low (deduped)" in r.stdout
    assert len(notified(tmp_path)) == 1


def test_alerts_again_after_window(tmp_path, proc):
    proc.meminfo(1_000_000)
    run("mem_watch.sh", env(tmp_path, proc))
    (tmp_path / "state" / "last_alert").write_text(str(int(time.time()) - 4000))
    run("mem_watch.sh", env(tmp_path, proc))
    assert len(notified(tmp_path)) == 2


def test_notify_failure_logged(tmp_path, proc):
    proc.meminfo(1_000_000)
    r = run("mem_watch.sh", env(tmp_path, proc, OOMG_NOTIFY="false"))
    assert "ALERT notify-failed" in r.stdout


def test_log_written(tmp_path, proc):
    proc.meminfo(3_000_000)
    run("mem_watch.sh", env(tmp_path, proc))
    assert "thresh=2048MB" in (tmp_path / "state" / "mem_watch.log").read_text()


def test_runs_prio_script_each_loop(tmp_path, proc):
    proc.meminfo(3_000_000)
    p = tmp_path / "prio.sh"
    p.write_text(f"echo ran >> {tmp_path}/prio_ran\n")
    run("mem_watch.sh", env(tmp_path, proc, OOMG_PRIO_SCRIPT=str(p)))
    run("mem_watch.sh", env(tmp_path, proc, OOMG_PRIO_SCRIPT=str(p)))
    assert (tmp_path / "prio_ran").read_text().count("ran") == 2
