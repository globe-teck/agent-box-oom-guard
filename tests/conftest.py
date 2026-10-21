import os, subprocess, json, pathlib, pytest

ROOT = pathlib.Path(__file__).resolve().parent.parent
BIN = ROOT / "bin"


class FakeProc:
    def __init__(self, base: pathlib.Path):
        self.base = base
        base.mkdir(parents=True, exist_ok=True)

    def add(self, pid, ppid, comm, args, adj=0, rss_kb=10240):
        d = self.base / str(pid)
        d.mkdir()
        (d / "comm").write_text(comm + "\n")
        (d / "cmdline").write_bytes(b"\0".join(a.encode() for a in args) + b"\0")
        (d / "stat").write_text(f"{pid} ({comm}) S {ppid} {pid} {pid} 0 -1\n")
        (d / "status").write_text(f"Name:\t{comm}\nVmRSS:\t{rss_kb} kB\n")
        (d / "oom_score_adj").write_text(f"{adj}\n")

    def adj(self, pid):
        return int((self.base / str(pid) / "oom_score_adj").read_text())

    def meminfo(self, avail_kb, swapfree_kb=0):
        (self.base / "meminfo").write_text(
            f"MemTotal: 16000000 kB\nMemAvailable: {avail_kb} kB\nSwapFree: {swapfree_kb} kB\n")


@pytest.fixture
def proc(tmp_path):
    return FakeProc(tmp_path / "proc")


@pytest.fixture
def cdp(tmp_path):
    """Fake CDP: a script that maps port -> JSON fixture file; logs every URL requested."""
    d = tmp_path / "cdp"; d.mkdir()
    log = tmp_path / "cdp.log"
    script = tmp_path / "fake_fetch.sh"
    script.write_text(f"""#!/usr/bin/env bash
echo "$1" >> {log}
port=${{1##*:}}; port=${{port%%/*}}
[ -f {d}/$port.json ] && cat {d}/$port.json || exit 7
""")
    script.chmod(0o755)

    class C:
        cmd = str(script)
        logfile = log
        def tabs(self, port, urls):
            (d / f"{port}.json").write_text(json.dumps(
                [{"type": "page", "url": u, "title": "t", "id": str(i)} for i, u in enumerate(urls)]))
    return C()


def run(script, env_extra, args=(), check=True):
    env = {"PATH": os.environ["PATH"], "HOME": os.environ.get("HOME", "/tmp")}
    env.update(env_extra)
    r = subprocess.run(["bash", str(BIN / script), *args], env=env, capture_output=True, text=True, timeout=30)
    if check:
        assert r.returncode == 0, r.stderr
    return r
