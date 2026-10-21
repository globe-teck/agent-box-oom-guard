import subprocess, os
from conftest import run, ROOT, BIN


def test_swapfile_dry_run_by_default(tmp_path):
    target = tmp_path / "swap.img"
    r = run("swapfile_setup.sh", {}, ["--path", str(target), "--size", "64M", "--persist"])
    assert "[dry-run]" in r.stdout and "fallocate -l 64M" in r.stdout and "mkswap" in r.stdout
    assert "Dry run only" in r.stdout
    assert not target.exists()


def test_swapfile_rejects_unknown_args():
    r = run("swapfile_setup.sh", {}, ["--bogus"], check=False)
    assert r.returncode == 2


def test_ensure_lock_makes_concurrent_run_noop(tmp_path):
    state = tmp_path / "state"; state.mkdir()
    lock = state / "ensure.lock"
    holder = subprocess.Popen(["flock", str(lock), "sleep", "3"])
    try:
        import time; time.sleep(0.3)
        r = run("oom_guard_ensure.sh", {"OOMG_STATE_DIR": str(state), "OOMG_EARLYOOM": "/nonexistent"})
        assert r.stdout == "" and not (state / "mem_watch.out").exists()
    finally:
        holder.kill()


def test_bashrc_snippet_has_no_interactive_guard_dependency():
    s = (ROOT / "examples" / "bashrc-snippet.sh").read_text()
    assert "oom_guard_ensure.sh" in s and "ABOVE the interactive guard" in s
