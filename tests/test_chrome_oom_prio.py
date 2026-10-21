from conftest import run


def setup_two_browsers(proc, cdp):
    # critical browser on port 9333
    proc.add(100, 1, "chrome", ["/opt/chrome/chrome", "--remote-debugging-port=9333", "--user-data-dir=/tmp/a"])
    proc.add(101, 100, "chrome", ["/opt/chrome/chrome", "--type=zygote"])
    proc.add(102, 101, "chrome", ["/opt/chrome/chrome", "--type=renderer"], adj=300)
    proc.add(103, 100, "chrome", ["/opt/chrome/chrome", "--type=gpu-process"])
    # ordinary browser on port 9444
    proc.add(200, 1, "chrome", ["/opt/chrome/chrome", "--remote-debugging-port=9444", "--user-data-dir=/tmp/b"])
    proc.add(201, 200, "chrome", ["/opt/chrome/chrome", "--type=zygote"])
    proc.add(202, 201, "chrome", ["/opt/chrome/chrome", "--type=renderer"], adj=300)
    proc.add(203, 200, "chrome", ["/opt/chrome/chrome", "--type=utility"])
    # unrelated process
    proc.add(300, 1, "node", ["node", "job.js"])
    cdp.tabs(9333, ["https://app.example.com/critical/dashboard", "https://example.org/"])
    cdp.tabs(9444, ["https://news.example.net/"])


def env(proc, cdp, **kw):
    e = {"OOMG_PROC_ROOT": str(proc.base), "OOMG_CDP_FETCH": cdp.cmd}
    e.update(kw)
    return e


def test_critical_browser_and_children_get_minus_500(proc, cdp):
    setup_two_browsers(proc, cdp)
    run("chrome_oom_prio.sh", env(proc, cdp))
    for pid in (100, 101, 102, 103):
        assert proc.adj(pid) == -500


def test_other_main_minus_100_renderer_plus_800(proc, cdp):
    setup_two_browsers(proc, cdp)
    run("chrome_oom_prio.sh", env(proc, cdp))
    assert proc.adj(200) == -100
    assert proc.adj(202) == 800
    assert proc.adj(201) == 0 and proc.adj(203) == 0  # non-renderer children untouched


def test_non_chrome_untouched(proc, cdp):
    setup_two_browsers(proc, cdp)
    run("chrome_oom_prio.sh", env(proc, cdp))
    assert proc.adj(300) == 0


def test_cdp_is_only_list_endpoint(proc, cdp):
    setup_two_browsers(proc, cdp)
    run("chrome_oom_prio.sh", env(proc, cdp))
    urls = cdp.logfile.read_text().split()
    assert sorted(urls) == ["http://localhost:9333/json/list", "http://localhost:9444/json/list"]


def test_custom_patterns(proc, cdp):
    setup_two_browsers(proc, cdp)
    run("chrome_oom_prio.sh", env(proc, cdp, OOMG_CRITICAL_PATTERNS=r"news\.example\.net"))
    assert proc.adj(200) == -500 and proc.adj(202) == -500
    assert proc.adj(100) == -100 and proc.adj(102) == 800


def test_pattern_must_match_url_not_title(proc, cdp):
    proc.add(100, 1, "chrome", ["chrome", "--remote-debugging-port=9333"])
    (proc.base.parent / "cdp" / "9333.json").write_text(
        '[{"title":"example.com/critical","url":"https://other.example/"}]')
    run("chrome_oom_prio.sh", env(proc, cdp))
    assert proc.adj(100) == -100


def test_no_debug_port_is_ordinary(proc, cdp):
    proc.add(100, 1, "chrome", ["chrome", "--user-data-dir=/tmp/x"])
    proc.add(101, 100, "chrome", ["chrome", "--type=renderer"])
    run("chrome_oom_prio.sh", env(proc, cdp))
    assert proc.adj(100) == -100 and proc.adj(101) == 800
    assert not cdp.logfile.exists()


def test_cdp_unreachable_is_ordinary(proc, cdp):
    proc.add(100, 1, "chrome", ["chrome", "--remote-debugging-port=9555"])
    run("chrome_oom_prio.sh", env(proc, cdp))
    assert proc.adj(100) == -100


def test_profile_regex_marks_critical(proc, cdp):
    proc.add(100, 1, "chrome", ["chrome", "--user-data-dir=/home/u/profiles/critical-1"])
    proc.add(101, 100, "chrome", ["chrome", "--type=renderer"])
    run("chrome_oom_prio.sh", env(proc, cdp, OOMG_CRITICAL_PROFILE_RE="critical-"))
    assert proc.adj(100) == -500 and proc.adj(101) == -500


def test_idempotent_and_reapplies_to_new_pids(proc, cdp):
    setup_two_browsers(proc, cdp)
    run("chrome_oom_prio.sh", env(proc, cdp))
    run("chrome_oom_prio.sh", env(proc, cdp))
    assert proc.adj(102) == -500 and proc.adj(202) == 800
    proc.add(204, 201, "chrome", ["chrome", "--type=renderer"])  # new tab
    proc.add(104, 101, "chrome", ["chrome", "--type=renderer"])
    run("chrome_oom_prio.sh", env(proc, cdp))
    assert proc.adj(204) == 800 and proc.adj(104) == -500


def test_dry_run_writes_nothing(proc, cdp):
    setup_two_browsers(proc, cdp)
    r = run("chrome_oom_prio.sh", env(proc, cdp, OOMG_DRY_RUN="1"))
    assert "would set pid=100 oom_score_adj=-500" in r.stdout
    assert proc.adj(100) == 0 and proc.adj(202) == 300


def test_comm_with_spaces_in_stat(proc, cdp):
    proc.add(100, 1, "chrome", ["chrome"])
    proc.add(150, 1, "my proc", ["x"])
    (proc.base / "150" / "stat").write_text("150 (my ) proc) S 100 1 1 0\n")
    proc.add(151, 150, "chrome", ["chrome", "--type=renderer"])
    run("chrome_oom_prio.sh", env(proc, cdp))
    assert proc.adj(151) == 800  # grandchild via odd comm still found
