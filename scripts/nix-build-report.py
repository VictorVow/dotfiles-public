#!/usr/bin/env python3
"""nix-build-report.py — report which top-level Home Manager packages needed
building (rather than substituting from a binary cache), and how long it took.

Usage:
  nix-build-report.py <since-epoch> <home-manager-path.drv>

How it works:
  The Nix daemon writes one log file per derivation it builds to
  /nix/var/log/nix/drvs/<2 chars>/<rest of drv name>.bz2. The file is created
  when the build starts (birth time) and last written when it finishes
  (mtime). Substituted paths produce no log. So every log with mtime after
  <since-epoch> is one locally-built derivation, with start/end timestamps.

  Each built derivation is then attributed to the top-level packages
  (inputDrvs of home-manager-path.drv) whose build closure contains it, found
  by walking the .drv files directly — far faster than `nix-store -qR` per
  package, since .drv closures include the whole bootstrap toolchain.

  Per package it prints two build-time totals (sum of each derivation's own
  build duration, from its log's birth to last write):
    only-this — derivations no other top-level package needs: roughly the time
                removing this one package from the config would save.
    shared    — derivations other top-level packages need too (e.g. a rebuilt
                perl), plus which packages they're shared with. Removing this
                package alone saves none of it; you'd have to drop them all.
  Builds run in parallel (max-jobs), so summed build time exceeds wall-clock.
"""

import os
import re
import subprocess
import sys

LOG_DIR = "/nix/var/log/nix/drvs"
# inputDrvs entries in the ATerm .drv format look like ("/nix/store/…drv",["out"]).
# inputSrcs are bare strings, so the tuple shape picks out only input derivations.
INPUT_DRV_RE = re.compile(rb'\("(/nix/store/[^"]+\.drv)",\[')
# Packages whose total build time is under this are wrappers/symlinkJoins
# (rebuilt locally whenever an input changes) — not worth listing individually.
TRIVIAL_SECS = 2
# How many co-dependent packages to name in the "shared with" column.
MAX_SHARED_NAMES = 3


def fmt_secs(s):
    if s is None:
        return "?"
    s = int(round(s))
    h, rem = divmod(s, 3600)
    m, s = divmod(rem, 60)
    if h:
        return f"{h}h{m:02d}m"
    if m:
        return f"{m}m{s:02d}s"
    return f"{s}s"


def strip_hash(path):
    """/nix/store/<hash>-name-1.2.drv → name-1.2"""
    base = os.path.basename(path)
    base = base.split("-", 1)[1] if "-" in base else base
    return base[:-4] if base.endswith(".drv") else base


def built_since(since):
    """{drv path: (start, end)} for every log written after `since`.

    Birth time comes from coreutils `stat` (statx) — neither Python's os.stat
    nor GNU find's %B expose it on Linux. start is None if it's unrecorded.
    """
    logs = []
    for sub in os.scandir(LOG_DIR):
        if not sub.is_dir():
            continue
        for f in os.scandir(sub.path):
            if f.stat().st_mtime >= since:
                logs.append(f.path)
    built = {}
    for i in range(0, len(logs), 500):
        out = subprocess.run(
            ["stat", "-c", "%W %.9Y %n", "--", *logs[i:i + 500]],
            capture_output=True, text=True, check=False,
        ).stdout
        for line in out.splitlines():
            birth, mtime, path = line.split(" ", 2)
            # …/drvs/<2 chars>/<rest>.drv.bz2 → /nix/store/<2 chars><rest>.drv
            rel = os.path.relpath(path, LOG_DIR).replace("/", "", 1).removesuffix(".bz2")
            start = float(birth) if birth not in ("-", "?") and float(birth) > 0 else None
            # Rebuilding a drv whose log already exists (e.g. never-substituted
            # runCommandLocal outputs that were GC'd) overwrites the file in
            # place, keeping the old birth time — so start isn't this build's.
            if start is not None and start < since:
                start = None
            built["/nix/store/" + rel] = (start, float(mtime))
    return built


def input_drvs(drv, cache):
    if drv not in cache:
        try:
            with open(drv, "rb") as f:
                cache[drv] = INPUT_DRV_RE.findall(f.read())
        except OSError:
            cache[drv] = []
    return cache[drv]


def built_closure(root, built, deps_cache, memo):
    """Set of built drvs within root's build closure (iterative post-order DFS)."""
    stack = [(root, False)]
    while stack:
        drv, expanded = stack.pop()
        if drv in memo:
            continue
        children = [c.decode() for c in input_drvs(drv, deps_cache)]
        if not expanded:
            stack.append((drv, True))
            stack.extend((c, False) for c in children if c not in memo)
            continue
        acc = {drv} if drv in built else set()
        for c in children:
            acc |= memo.get(c, set())
        memo[drv] = frozenset(acc)
    return memo[root]


def duration(times):
    start, end = times
    return 0.0 if start is None else end - start


def main():
    if len(sys.argv) != 3:
        print(__doc__.split("\n\n")[1], file=sys.stderr)
        sys.exit(2)
    since, hm_path_drv = float(sys.argv[1]), sys.argv[2]

    built = built_since(since)
    if not built:
        print("  Nothing was built locally — everything came from binary caches.")
        return
    secs = {d: duration(t) for d, t in built.items()}

    # Built closure of every top-level package, and the reverse: which
    # top-level packages need each built derivation.
    deps_cache, memo = {}, {}
    closures, needed_by = {}, {}
    for top in input_drvs(hm_path_drv, deps_cache):
        top = top.decode()
        mine = built_closure(top, built, deps_cache, memo)
        if mine:
            closures[top] = mine
            for d in mine:
                needed_by.setdefault(d, set()).add(top)

    rows, trivial = [], 0
    for top, mine in closures.items():
        only = [d for d in mine if len(needed_by[d]) == 1]
        shared = [d for d in mine if len(needed_by[d]) > 1]
        only_secs = sum(secs[d] for d in only)
        shared_secs = sum(secs[d] for d in shared)
        if only_secs + shared_secs < TRIVIAL_SECS:
            trivial += 1
            continue
        # Co-dependents ranked by how much shared build time they account for.
        weight = {}
        for d in shared:
            for other in needed_by[d] - {top}:
                weight[other] = weight.get(other, 0) + secs[d]
        others = sorted(weight, key=weight.get, reverse=True)
        names = ", ".join(strip_hash(o) for o in others[:MAX_SHARED_NAMES])
        if len(others) > MAX_SHARED_NAMES:
            names += f" +{len(others) - MAX_SHARED_NAMES} more"
        rows.append((only_secs, shared_secs, strip_hash(top), len(only), len(shared), names))

    if rows:
        rows.sort(key=lambda r: (r[0] + r[1], r[0]), reverse=True)
        width = max(len("PACKAGE"), *(len(r[2]) for r in rows))
        print(f"  {'PACKAGE':<{width}}  {'ONLY-THIS':>14}  {'SHARED':>14}  SHARED WITH")
        for only_secs, shared_secs, name, n_only, n_shared, names in rows:
            only_col = f"{fmt_secs(only_secs)} ({n_only})" if n_only else "-"
            shared_col = f"{fmt_secs(shared_secs)} ({n_shared})" if n_shared else "-"
            print(f"  {name:<{width}}  {only_col:>14}  {shared_col:>14}  {names}".rstrip())
        print("  (build time summed per derivation; derivation count in brackets)")
    if trivial:
        print(f"  (+ {trivial} wrapper package(s) rebuilt in <{TRIVIAL_SECS}s each)")

    unattributed = [d for d in built if d not in needed_by]
    if unattributed:
        print(f"  Not part of any package (HM config files, activation, etc.): "
              f"{len(unattributed)} derivation(s), {fmt_secs(sum(secs[d] for d in unattributed))}")

    known = [v for v in built.values() if v[0] is not None]
    wall = max(e for _, e in known) - min(s for s, _ in known) if known else None
    print(f"  Total: {len(built)} derivation(s), {fmt_secs(sum(secs.values()))} build time, "
          f"{fmt_secs(wall)} wall-clock.")


if __name__ == "__main__":
    main()
