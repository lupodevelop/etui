#!/usr/bin/env python3
"""Exercise intentional Unicode regressions in a temporary checkout.

Run with: python3 dev/check_unicode_mutations.py
Only assertion failures kill a mutant. Compilation errors, timeouts and
surviving mutations make the check fail. The working tree is never edited.
"""

from dataclasses import dataclass
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parent.parent
ANSI = re.compile(r"\x1b\[[0-?]*[ -/]*[@-~]")
TEXT = "src/etui/text.gleam"
FFI = "src/etui_buffer_array_ffi.erl"


@dataclass(frozen=True)
class Mutation:
    name: str
    path: str
    before: str
    after: str
    occurrences: int = 1
    targets: tuple = ("erlang", "javascript")


MUTATIONS = [
    Mutation("ignore VS16", TEXT,
             "True if selector == 0xFE0F -> 2", "True if selector == 0xFE0F -> 1"),
    Mutation("ignore VS15", TEXT,
             "True if base < 0x1F000 -> 1", "True if base < 0x1F000 -> codepoint_cell_width(base)"),
    Mutation("narrow supplementary emoji", TEXT,
             "True if base < 0x1F000 -> 1", "True -> 1"),
    Mutation("accept unsupported bases", TEXT,
             "case emoji_variation_base(base) {", "case base >= 0 {"),
    Mutation("drop a Unicode table entry", TEXT,
             "0x23CF -> True", "0x23CF -> False"),
    Mutation("move a Unicode range boundary", TEXT,
             "n if n >= 0x2194 && n <= 0x2199 -> True",
             "n if n >= 0x2195 && n <= 0x2199 -> True"),
    Mutation("accept a neighbour outside a Unicode range", TEXT,
             "n if n >= 0x2194 && n <= 0x2199 -> True",
             "n if n >= 0x2193 && n <= 0x2199 -> True"),
    Mutation("ignore selectors during Erlang fill", FFI,
             "'etui@text':grapheme_cell_width(GBin)", "cp_width(hd(GList))",
             targets=("erlang",)),
    Mutation("split ASCII keycaps", FFI,
             ",\n             (Rest =:= <<>> orelse binary_part(Rest, 0, 1) < <<16#80>>)", "",
             occurrences=2, targets=("erlang",)),
    Mutation("clip a fitting direct write", FFI,
             "when W >= 2, Idx + 1 >= MaxIdx ->", "when W >= 2, Idx + 2 >= MaxIdx ->",
             targets=("erlang",)),
    Mutation("overflow bulk fills", FFI,
             "W when W >= 2, Col + 1 >= Width ->", "W when W >= 2, Col >= Width ->",
             targets=("erlang",)),
]


def run_tests(work, target):
    try:
        result = subprocess.run(
            ["gleam", "test", "--target", target], cwd=work,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=60,
        )
    except subprocess.TimeoutExpired:
        return "timeout", "Suite did not finish within 60 seconds."
    output = ANSI.sub("", result.stdout)
    if result.returncode == 0 and re.search(r"\b\d+ passed, no failures\b", output):
        return "passed", output
    if (re.search(r"\b\d+ passed, [1-9]\d* failures\b", output)
            and "src/gleeunit/should.gleam" in output):
        return "assertion failure", output
    return "invalid run", output


def main():
    failed = False
    with tempfile.TemporaryDirectory(prefix="etui-unicode-mutations-") as tmp:
        work = Path(tmp) / "etui"
        # Copy only build inputs and caches, including uncommitted tests.
        for name in ("src", "test", "dev", "build"):
            shutil.copytree(ROOT / name, work / name)
        for name in ("gleam.toml", "manifest.toml"):
            shutil.copy2(ROOT / name, work / name)
        for target in ("erlang", "javascript"):
            status, output = run_tests(work, target)
            if status != "passed":
                print(f"Baseline failed ({target}): {status}\n{output}")
                return 1
            print(f"baseline passed ({target})", flush=True)
        for mutation in MUTATIONS:
            path = work / mutation.path
            original = path.read_text()
            if original.count(mutation.before) != mutation.occurrences:
                print(f"stale mutation: {mutation.name}", flush=True)
                failed = True
                continue
            try:
                path.write_text(original.replace(mutation.before, mutation.after))
                for target in mutation.targets:
                    status, output = run_tests(work, target)
                    killed = status == "assertion failure"
                    label = "killed" if killed else f"FAILED ({status})"
                    print(f"{label} ({target}): {mutation.name}", flush=True)
                    if not killed:
                        failed = True
                        print(output[-4000:], flush=True)
            finally:
                path.write_text(original)
    return int(failed)


if __name__ == "__main__":
    sys.exit(main())
