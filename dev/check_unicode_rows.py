#!/usr/bin/env python3
"""Compare canonical Unicode corpus cells from Erlang and JavaScript."""

from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent.parent


def capture(target):
    result = subprocess.run(
        ["gleam", "run", "--target", target, "-m", "unicode_rows"],
        cwd=ROOT, capture_output=True, text=True, timeout=60,
    )
    if result.returncode:
        raise RuntimeError(f"{target} corpus failed:\n{result.stderr}\n{result.stdout}")
    rows = {}
    for line in result.stdout.splitlines():
        if line.startswith("ROW "):
            _, key, cells = line.split(" ", 2)
            if key in rows:
                raise RuntimeError(f"Duplicate corpus entry: {key}")
            rows[key] = cells
    if not rows:
        raise RuntimeError(f"{target} emitted no corpus cells")
    # Check expected IDs independently, so two truncated outputs cannot pass.
    expected = {
        f"{seed}/{start}/{operation}"
        for seed in range(256)
        for start in {-1, 0, seed % 13 - 1, seed % 13}
        for operation in ("linked", "bulk", "original")
    }
    if rows.keys() != expected:
        raise RuntimeError(f"{target} corpus is incomplete or contains unexpected IDs")
    return rows


def main():
    erlang = capture("erlang")
    javascript = capture("javascript")
    mismatches = [key for key in erlang if erlang[key] != javascript[key]]
    if mismatches:
        key = mismatches[0]
        raise RuntimeError(
            f"Corpus mismatch {key}\nErlang: {erlang[key]}\nJavaScript: {javascript[key]}"
        )
    print("Unicode corpus cells match across Erlang and JavaScript")


if __name__ == "__main__":
    main()
