#!/usr/bin/env python3
"""Mutation testing: inject each bug in mutations/ and record which flow catches it.

Each mutant runs in a throwaway copy, build/mutation/<id>/ (never in the repo,
so an interrupted run cannot leave a bug in the real RTL):
  1. sanity: the patch applies, the mutant compiles, and its behaviour
     signature (props_sim without assertions: a hash of every DUT output and
     internal register over 200k random cycles) differs from the clean
     design's. Same signature = equivalent mutant, reported as such, not as missed.
  2. simulation: `make regress UVM_CHECKERS=no` (black-box UVM: scoreboard,
     monitors, coverage checks; the formal checkers are not bound in).
  3. formal: `make formal` (Questa PropCheck) if qverify is on PATH, else
     props-sim (the same properties in a random simulation) as a local proxy,
     labelled as such: it is not a proof.
Writes build/mutation/summary.md; exits 1 if any non-equivalent mutant is
missed by every flow that ran, or the clean design fails.

  python3 scripts/run_mutations.py                   (or: make mutate)
  python3 scripts/run_mutations.py --only M05,M16 --seeds 3

Runs from the repo root. Python 3.6 compatible (the Questa machine).
"""
import argparse
import datetime
import glob
import os
import re
import shutil
import subprocess
import sys

OUT = "build/mutation"
COPY = ["rtl", "tb", "formal", "scripts", "docs", "Makefile"]


def sh(cmd, cwd, log):
    """Run a command in cwd, write its output to log; (exit code, output).
    A missing tool is exit code 127, not a crash."""
    try:
        p = subprocess.run(cmd, cwd=cwd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                           universal_newlines=True)
        code, out = p.returncode, p.stdout
    except OSError as e:
        code, out = 127, "run_mutations: cannot run %s: %s\n" % (cmd[0], e)
    with open(log, "w") as f:
        f.write(out)
    return code, out


def describe(patch):
    first = open(patch).readline().strip()
    return first[2:].split(": ", 1)[1] if first.startswith("# ") and ": " in first else os.path.basename(patch)


def prepare(mid, patch):
    """Fresh copy of the sources in build/mutation/<mid>/, patch applied."""
    d = os.path.join(OUT, mid)
    if os.path.isdir(d):
        shutil.rmtree(d)
    os.makedirs(os.path.join(d, "build"))      # Verilator does not create the parent of -Mdir
    for item in COPY:
        if os.path.isdir(item):
            shutil.copytree(item, os.path.join(d, item))
        else:
            shutil.copy(item, d)
    if patch is None:
        return d, True
    # `patch -p1`, not `git apply`: the copy sits inside this repo's work tree,
    # where `git apply` takes paths relative to the repo root, silently skips
    # everything outside the current directory and still exits 0. So the
    # result is checked too: at least one file must really have changed.
    code, _ = sh(["patch", "-p1", "--batch", "--forward", "--input", os.path.abspath(patch)],
                 d, os.path.join(d, "apply.log"))
    changed = any(open(os.path.join(d, f)).read() != open(f).read()
                  for f in re.findall(r"^\+\+\+ b/(\S+)", open(patch).read(), re.M))
    return d, code == 0 and changed


def signature(d):
    """Build props_sim with no checkers bound (JTAG_NO_CHECKERS: Verilator
    evaluates concurrent assertions even without --assert, and one firing would
    stop the run) and return (compiled, signature or None)."""
    code, _ = sh(["verilator", "--binary", "--timing", "--timescale", "1ns/1ps", "-Wno-fatal", "-Wno-lint",
                  "-Wno-style", "+define+JTAG_NO_CHECKERS", "--top-module", "props_sim", "-Mdir", "build/sig",
                  "-f", "rtl/rtl.f", "-f", "formal/formal.f", "formal/props_sim.sv"],
                 d, os.path.join(d, "sig_build.log"))
    if code != 0:
        return False, None
    _, out = sh(["build/sig/Vprops_sim"], d, os.path.join(d, "sig_run.log"))
    m = re.search(r"PROPS SIM SIGNATURE: ([0-9a-f]+)", out)
    return True, m.group(1) if m else None


def first_failure(summary):
    """First failing row of a regress summary.md: 'test seed: error'."""
    for line in summary.splitlines():
        cells = [c.strip() for c in line.split("|")]
        if len(cells) > 7 and cells[3] == "FAIL":
            return "%s s%s: %s" % (cells[1], cells[2], cells[7][:90])
    return ""


def sim_verdict(code, out, summary):
    """(caught, detail) from a `make regress` run. Caught needs a failing run
    in summary.md: a non-zero exit alone (a failed seed check, a crash before
    the summary) is an error, not a catch."""
    if "build failed" in out:
        return None, "UVM build failed"
    fail = first_failure(summary)
    if fail:
        return True, fail
    if code != 0:
        return None, "regress failed without a failing run (see sim.log)"
    return False, ""


def score_sim(d, seeds):
    code, out = sh(["make", "regress", "SEEDS=%d" % seeds, "UVM_CHECKERS=no"], d, os.path.join(d, "sim.log"))
    path = os.path.join(d, "build/regress/summary.md")
    summary = open(path).read() if os.path.exists(path) else ""
    return sim_verdict(code, out, summary)


def score_props(d):
    code, out = sh(["make", "props-sim"], d, os.path.join(d, "props.log"))
    m = re.search(r"Assertion failed in \S+\.(\w+)", out)
    if m:
        return True, m.group(1)
    if "PROPS SIM DONE" not in out:
        return None, "props-sim did not run (see props.log)"
    return False, ""


FAIL_WORDS = r"(?:fired|falsified|violated|cex)"


def formal_counts(text):
    """(proven, failed) assertion counts from a Questa formal report, or
    (None, None) if the report is not understood. The format is not verified
    yet, so the clean design's report is checked with this first (main())."""
    def count(word):
        # "Proven : 63" (number right after, only ':' '=' or blanks between) or
        # "63 assertions proven" (number before); never across a line break
        m = (re.search(r"\b%s\b[ \t]*[:=]?[ \t]*(\d+)" % word, text, re.I) or
             re.search(r"(\d+)[ \t]+(?:assertions?[ \t]+)?%s\b" % word, text, re.I))
        return int(m.group(1)) if m else None
    proven = count("proven")
    failed = [count(w) for w in ("fired", "falsified", "violated", "cex")]
    if proven is None:
        return None, None
    return proven, sum(c for c in failed if c is not None)


def expected_assertions():
    """Number of assertions in formal/: every `name: assert property` plus every
    `ASSERT_TRST(a_…)`. Derived from the source, so it stays right when a
    property is added; the clean formal run must prove exactly this many."""
    n = 0
    for f in glob.glob("formal/*.sv") + glob.glob("formal/*.svh"):
        text = open(f).read()
        n += len(re.findall(r"^\s*a_\w+\s*:\s*assert\s+property\b", text, re.M))
        n += len(re.findall(r"`ASSERT_TRST\(\s*a_\w+", text))
    return n


def formal_names(text):
    """Names of failing assertions, for the detail column only."""
    names = re.findall(r"\b(a_\w+)\b[^\n]*\b%s\b" % FAIL_WORDS, text, re.I)
    names += re.findall(r"\b%s\b[^\n]*\b(a_\w+)\b" % FAIL_WORDS, text, re.I)
    return sorted(set(names))


def score_formal(d, expect_proven=None):
    """Questa PropCheck: caught if the report counts at least one failed
    assertion; the names are only the detail. With expect_proven (the clean
    design), the report must show exactly that many proven and none failed:
    this checks that the parser reads the right table, and that the reference
    run has nothing inconclusive."""
    code, out = sh(["make", "formal"], d, os.path.join(d, "formal.log"))
    report = os.path.join(d, "build/formal/formal_report.txt")
    if not os.path.exists(report):
        return None, "no formal report (see formal.log)"
    text = open(report).read()
    proven, failed = formal_counts(text)
    if proven is None or proven == 0:
        return None, "formal report not understood or shows nothing proven (see build/formal/formal_report.txt)"
    if expect_proven is not None and (proven != expect_proven or failed != 0):
        return None, "clean report shows %d proven (expected %d) and %d failed" % (proven, expect_proven, failed)
    names = formal_names(text)
    return failed > 0, "%d failed, %d proven%s" % (failed, proven, (": " + ", ".join(names[:4]) + (" …" if len(names) > 4 else ""))
                                                    if names else "")


def cell(result, detail):
    if result is None:
        return "error: " + detail
    return ("**caught**: " + detail) if result else "missed"


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--only", help="comma-separated mutant IDs, e.g. M05,M16")
    ap.add_argument("--seeds", type=int, default=5, help="random-test seeds in the simulation regression")
    ap.add_argument("--formal", choices=["auto", "questa", "proxy"], default="auto",
                    help="auto: Questa if qverify is on PATH, else the props-sim proxy")
    args = ap.parse_args()
    # Every path below is repo-root-relative: work from there, wherever we were started
    os.chdir(os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

    patches = sorted(glob.glob("mutations/M*.patch"))
    if args.only:
        wanted = set(args.only.split(","))
        patches = [p for p in patches if os.path.basename(p).split("_")[0] in wanted]
    use_questa = args.formal == "questa" or (args.formal == "auto" and shutil.which("qverify"))
    formal_name = "Formal (Questa PropCheck)" if use_questa else "Formal proxy (props-sim, not a proof)"
    os.makedirs(OUT, exist_ok=True)

    # The clean design must pass everything; its signature is the reference
    print("clean design ...", flush=True)
    d, _ = prepare("clean", None)
    _, clean_sig = signature(d)
    sim, _ = score_sim(d, args.seeds)
    expected = expected_assertions()
    if use_questa and expected == 0:
        sys.exit("run_mutations: no assertions found in formal/ (run from the repo root)")
    frm, frm_detail = score_formal(d, expected) if use_questa else score_props(d)
    # The measuring tools are validated on the clean design before they measure:
    # signature, a passing regression, and a formal report the parser
    # understands and that shows no failure
    if clean_sig is None or sim is not False or frm is not False:
        sys.exit("run_mutations: the clean design does not pass, or its results are not understood "
                 "(signature %s, simulation %s, formal %s: %s); see %s/clean/" % (clean_sig, sim, frm, frm_detail, OUT))

    rows, n_eq, n_sim, n_frm, n_both, n_missed, n_err = [], 0, 0, 0, 0, 0, 0
    for patch in patches:
        mid = os.path.basename(patch).split("_")[0]
        print("%s ..." % mid, flush=True)
        d, applied = prepare(mid, patch)
        if not applied:
            rows.append((mid, describe(patch), "patch does not apply", "", ""))
            n_err += 1
            continue
        compiled, sig = signature(d)
        if sig is None:
            rows.append((mid, describe(patch), "does not compile" if not compiled else
                         "signature run did not finish (see sig_run.log)", "", ""))
            n_err += 1
            continue
        if sig == clean_sig:
            # A heuristic, not a proof: confirm with formal and the patch before
            # calling it equivalent anywhere public
            rows.append((mid, describe(patch), "**no difference** in 200k random cycles (equivalent?)", "", ""))
            n_eq += 1
            continue
        sim, sim_detail = score_sim(d, args.seeds)
        frm, frm_detail = score_formal(d) if use_questa else score_props(d)
        n_err += sim is None or frm is None
        n_sim += bool(sim)
        n_frm += bool(frm)
        n_both += bool(sim) and bool(frm)
        n_missed += (sim is False) and (frm is False)
        rows.append((mid, describe(patch), "yes", cell(sim, sim_detail), cell(frm, frm_detail)))

    n = len(rows)
    md = ["# Mutation summary", "",
          "%s; simulation: `make regress SEEDS=%d UVM_CHECKERS=no` (black-box UVM); formal: %s" % (
              datetime.date.today().isoformat(), args.seeds, formal_name), "",
          "| ID | Mutation | Behaviour changed | Simulation (UVM) | %s |" % formal_name,
          "|---|---|---|---|---|"]
    md += ["| %s | %s | %s | %s | %s |" % r for r in rows]
    md += ["",
           "**%d mutants:** caught by simulation %d, by %s %d, by both %d; missed by both %d; "
           "no difference in 200k random cycles %d; errors %d." % (
               n, n_sim, "formal" if use_questa else "the formal proxy", n_frm, n_both, n_missed, n_eq, n_err)]
    summary = os.path.join(OUT, "summary.md")
    with open(summary, "w") as f:
        f.write("\n".join(md) + "\n")
    print("\n".join(md))
    print("\nwritten: %s (one directory per mutant in %s/)" % (summary, OUT))
    sys.exit(0 if n_missed == 0 and n_err == 0 else 1)


if __name__ == "__main__":
    main()
