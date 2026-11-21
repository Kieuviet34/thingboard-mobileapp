"""Fail when line coverage (from lcov.info) is below the agreed floors.

Usage:
  python -I tools/qa/check_coverage.py --min 80 --floor lib/core/api=80 --floor lib/widgets=80

`--min` applies to all of `lib/`. Each `--floor PREFIX=PERCENT` applies to files under that
path prefix. Generated code is ignored. Exit code 1 on any shortfall.
"""

import argparse
import sys

GENERATED_SUFFIXES = (".g.dart", ".freezed.dart", ".gr.dart")


def read_lcov(path):
    files, current = {}, None
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.strip()
            if line.startswith("SF:"):
                current = line[3:].replace("\\", "/")
                files[current] = [0, 0]  # [lines found, lines hit]
            elif line.startswith("LF:") and current:
                files[current][0] = int(line[3:])
            elif line.startswith("LH:") and current:
                files[current][1] = int(line[3:])
    return {
        name: counts
        for name, counts in files.items()
        if name.startswith("lib/") and not name.endswith(GENERATED_SUFFIXES)
    }


def percent(found, hit):
    return 100.0 if found == 0 else 100.0 * hit / found


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--lcov", default="coverage/lcov.info")
    parser.add_argument("--min", type=float, default=0.0, help="minimum percent for all of lib/")
    parser.add_argument("--floor", action="append", default=[], metavar="PREFIX=PERCENT")
    args = parser.parse_args()

    files = read_lcov(args.lcov)
    if not files:
        print(f"No lib/ entries found in {args.lcov}. Did `flutter test --coverage` run?")
        return 1

    failures = []
    found = sum(c[0] for c in files.values())
    hit = sum(c[1] for c in files.values())
    total = percent(found, hit)
    print(f"lib/ total: {hit}/{found} lines = {total:.1f}% (floor {args.min:.0f}%)")
    if total < args.min:
        failures.append(f"lib/ total {total:.1f}% < {args.min:.0f}%")

    for spec in args.floor:
        prefix, _, minimum = spec.partition("=")
        selected = [c for n, c in files.items() if n.startswith(prefix.rstrip("/") + "/")]
        if not selected:
            failures.append(f"{prefix}: no files found (typo in --floor?)")
            continue
        f, h = sum(c[0] for c in selected), sum(c[1] for c in selected)
        pct = percent(f, h)
        print(f"{prefix}: {h}/{f} lines = {pct:.1f}% (floor {float(minimum):.0f}%)")
        if pct < float(minimum):
            failures.append(f"{prefix} {pct:.1f}% < {float(minimum):.0f}%")

    if failures:
        print("\nCoverage check FAILED:")
        for failure in failures:
            print(f"  - {failure}")
        return 1
    print("\nCoverage check passed.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
