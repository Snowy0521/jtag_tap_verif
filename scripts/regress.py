#!/usr/bin/env python3
"""Regression: every directed test once, plus the random test on N seeds.

Builds once, runs every test, decides pass / fail per run, merges the TB
coverage counters (every simulator) and, on QuestaSim, merges the UCDBs with
vcover (functional coverage from the covergroups, plus RTL code coverage).
Writes build/regress/summary.md and exits 1 if any run failed or the seed
check fails.

  python3 scripts/regress.py --sim verilator --seeds 20     (or: make regress)
  python3 scripts/regress.py --sim questa    --seeds 20     (or: make regress-questa)

Runs from the repo root. Python 3.6 compatible (the Questa machine).
"""
import argparse
import collections
import concurrent.futures
import datetime
import glob
import os
import re
import subprocess
import sys

DIRECTED = ["jtag_reset_test", "jtag_idcode_test", "jtag_bypass_test",
            "jtag_unused_opcode_test", "jtag_dft_test", "jtag_pause_test"]
RANDOM = "jtag_random_test"
OUT = "build/regress"


def sh(cmd, log=None):
    """Run a command, return (exit code, combined output). A missing tool is a
    normal failure (127, like a shell), not a crash: the summary still gets written."""
    try:
        p = subprocess.run(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True)
        code, out = p.returncode, p.stdout
    except OSError as e:
        code, out = 127, "regress: cannot run %s: %s\n" % (cmd[0], e)
    if log:
        with open(log, "w") as f:
            f.write(out)
    return code, out


def verdict(text, sim):
    """PASS only with a complete UVM summary, no UVM errors and no simulator errors
    (a failing bound property is not a UVM_ERROR)."""
    if not re.search(r"UVM_ERROR :\s+0\b", text) or not re.search(r"UVM_FATAL :\s+0\b", text):
        return False
    sim_error = r"%Error" if sim == "verilator" else r"\*\* (Error|Fatal)"
    return re.search(sim_error, text) is None


def first_error(text):
    for pat in (r"UVM_(ERROR|FATAL) \S+ @ \d+: \S+ (\[\w+\][^\n]{0,90})",
                r"(%Error[^\n]{0,110})", r"(\*\* (Error|Fatal)[^\n]{0,110})"):
        m = re.search(pat, text)
        if m:
            return m.group(m.lastindex if pat.startswith("UVM") else 1)
    return "no UVM summary (crash or hang?)"


def counters(text):
    """TB coverage counters printed with +cov_dump: {bin: count}."""
    return {m.group(1): int(m.group(2)) for m in re.finditer(r"^COV (\S+) (\d+)$", text, re.M)}


def stats(text):
    m = re.search(r"(\d+) scans, (\d+) TDO bits matched", text)
    return (int(m.group(1)), int(m.group(2))) if m else (0, 0)


# ---------------------------------------------------------------- simulators
def build(sim):
    target = "uvm-build" if sim == "verilator" else "sim-build"
    code, out = sh(["make", target], log=os.path.join(OUT, "build.log"))
    if code != 0:
        sys.exit("regress: build failed, see %s/build.log" % OUT)


def remove(path):
    if os.path.exists(path):
        os.remove(path)


def run(sim, test, seed):
    """One run: (test, seed, exit code, log text). The exit code is a second
    opinion next to the log verdict: a run fails if either says so."""
    log = os.path.join(OUT, "%s_%d.log" % (test, seed))
    remove(log)
    if sim == "verilator":
        code, text = sh(["build/uvm/Vtb_top", "+UVM_TESTNAME=" + test, "+verilator+seed+%d" % seed,
                         "+verilator+rand+reset+2", "+cov_dump"], log=log)
    else:
        # Not run on this machine yet: the Makefile's sim-run (one vsim run,
        # log in build/sim/, UCDB in build/cov/). The old log and UCDB are
        # removed first, so a run that dies before vsim writes them can never
        # be judged on the previous regression's files.
        sim_log = "build/sim/%s_%d.log" % (test, seed)
        remove(sim_log)
        remove(ucdb_of(test, seed))
        code, _ = sh(["make", "sim-run", "TEST=" + test, "SEED=%d" % seed, "PLUSARGS=+cov_dump"])
        text = open(sim_log).read() if os.path.exists(sim_log) else ""
        with open(log, "w") as f:
            f.write(text)
    return test, seed, code, text


def ucdb_of(test, seed):
    return "build/cov/%s_%d.ucdb" % (test, seed)


def vcover_merge(ucdbs):
    """Merge the given UCDBs (passing runs only). Returns (ok, summary lines);
    ok is False if anything needed for the sign-off number is missing or
    failed (Questa only)."""
    missing = [u for u in ucdbs if not os.path.exists(u)]
    if missing:
        return False, ["missing UCDBs of passing runs: " + ", ".join(missing)]
    if not ucdbs:
        return False, ["no passing run: nothing to merge"]
    code, out = sh(["vcover", "merge", "build/cov/merged.ucdb"] + ucdbs,
                   log=os.path.join(OUT, "vcover_merge.log"))
    if code != 0:
        return False, ["vcover merge failed, see %s/vcover_merge.log" % OUT]
    code, out = sh(["vcover", "report", "-summary", "build/cov/merged.ucdb"],
                   log=os.path.join(OUT, "coverage_summary.txt"))
    if code != 0:
        code, out = sh(["vcover", "report", "build/cov/merged.ucdb"],
                       log=os.path.join(OUT, "coverage_summary.txt"))
    if code != 0:
        return False, ["vcover report failed, see %s/coverage_summary.txt" % OUT]
    keep = re.compile(r"(Covergroups|Coverpoints|Cross|Statements|Branches|Conditions|Expressions|"
                      r"FSM|Toggles|Assertions|Directives|Total)", re.I)
    lines = [l.rstrip() for l in out.splitlines() if keep.search(l)]
    # Unrecognised lines are a formatting question, not a failed merge
    return True, lines or ["(no summary lines recognised; full report in %s/coverage_summary.txt)" % OUT]


# ---------------------------------------------------------------- main
def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--sim", choices=["verilator", "questa"], default="verilator")
    ap.add_argument("--seeds", type=int, default=20, help="seeds for the random test (1..N)")
    ap.add_argument("--jobs", type=int, default=os.cpu_count() or 4,
                    help="parallel runs (Verilator only; Questa runs one at a time)")
    args = ap.parse_args()

    os.makedirs(OUT, exist_ok=True)
    if args.sim == "questa":
        for f in glob.glob("build/cov/*.ucdb"):       # this regression's UCDBs only
            os.remove(f)
    build(args.sim)

    runs = [(t, 1) for t in DIRECTED] + [(RANDOM, s) for s in range(1, args.seeds + 1)]
    jobs = args.jobs if args.sim == "verilator" else 1
    with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as pool:
        results = list(pool.map(lambda r: run(args.sim, r[0], r[1]), runs))

    # Coverage counts only from passing runs: a failed run is no evidence that
    # anything was tested correctly
    rows, merged, merged_random = [], collections.Counter(), collections.Counter()
    best_random, failed, random_passed = 0, 0, 0
    passing_ucdbs, random_sigs = [], collections.defaultdict(list)
    for test, seed, code, text in results:
        ok = code == 0 and verdict(text, args.sim)
        failed += not ok
        cnt = counters(text)
        hit = sum(1 for v in cnt.values() if v)
        scans, bits = stats(text)
        if ok:
            merged.update(cnt)
            passing_ucdbs.append(ucdb_of(test, seed))
            if test == RANDOM:
                merged_random.update(cnt)
                best_random = max(best_random, hit)
                random_passed += 1
                # Y3: a run's signature; two seeds with the same one did the same thing
                random_sigs[(scans, bits, tuple(sorted(cnt.items())))].append(seed)
        if ok:
            err = ""
        elif not verdict(text, args.sim):
            err = first_error(text)
        else:
            err = "exit code %d (log looks clean)" % code
        rows.append((test, seed, "PASS" if ok else "FAIL", scans, bits, hit, len(cnt), err))

    n_bins = len(merged)
    n_hit = sum(1 for v in merged.values() if v)
    holes = sorted(k for k, v in merged.items() if not v)
    rnd_hit = sum(1 for v in merged_random.values() if v)
    # The seeds must really differ. Direct: no two passing seeds with the same
    # scan count, TDO bit count and coverage counts. Indirect: their merge beats
    # the best single seed (says nothing once one seed hits every bin).
    seed_checked = random_passed >= 2
    identical = [s for s in random_sigs.values() if len(s) > 1]
    seed_ok = not seed_checked or (not identical and (rnd_hit > best_random or rnd_hit == n_bins))

    md = ["# Regression summary", "",
          "%s, %s; %d directed tests + %s on seeds 1..%d" % (
              args.sim, datetime.date.today().isoformat(), len(DIRECTED), RANDOM, args.seeds), "",
          "| Test | Seed | Result | Scans | TDO bits | TB bins hit | First error |",
          "|---|---|---|---|---|---|---|"]
    for t, s, r, sc, b, h, n, e in rows:
        md.append("| %s | %d | %s | %d | %d | %d / %d | %s |" % (t, s, r, sc, b, h, n, e))
    md += ["",
           "**Runs:** %d passed, %d failed." % (len(rows) - failed, failed), "",
           "**Merged functional coverage (TB counters, passing runs only):** %d / %d bins (%.1f %%)%s" % (
               n_hit, n_bins, 100.0 * n_hit / max(n_bins, 1),
               "" if not holes else "; holes: " + ", ".join(holes)), "",
           "**Seed check:** " + (
               "%s: %d passing seeds, all different runs: %s; merged %d bins, best single seed %d: %s" % (
                   RANDOM, random_passed, "no, identical seeds " + str(identical) if identical else "yes",
                   rnd_hit, best_random, "OK" if seed_ok else "FAILED")
               if seed_checked else "not evaluated (fewer than 2 passing seeds of %s)" % RANDOM)]
    cov_ok = True
    if args.sim == "questa":
        cov_ok, cov_lines = vcover_merge(passing_ucdbs)
        md += ["", "**vcover merge of the %d passing runs (build/cov/merged.ucdb):** %s" % (
                   len(passing_ucdbs), "OK" if cov_ok else "FAILED"),
               "", "```"] + cov_lines + ["```"]

    summary = os.path.join(OUT, "summary.md")
    with open(summary, "w") as f:
        f.write("\n".join(md) + "\n")
    print("\n".join(md))
    print("\nwritten: %s (logs in %s/)" % (summary, OUT))
    # A failed or incomplete coverage merge fails the regression too: the
    # sign-off number must never come from it
    sys.exit(0 if failed == 0 and seed_ok and cov_ok else 1)


if __name__ == "__main__":
    main()
