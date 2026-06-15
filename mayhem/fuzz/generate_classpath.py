#!/usr/bin/env python3
"""generate_classpath.py — emit the Java classpath for the chesslib Jazzer target.

Port of the old fork's fuzz/generate_classpath.py (which printed a jar manifest Class-Path line).
Here it prints a single ':'-joined classpath of the harness classes dir plus every jar in the
fuzz-deps dir (library + runtime deps + jazzer runtime). build.sh writes the result to
/mayhem/fuzz-classpath.txt for reference; the Mayhemfile uses the equivalent wildcard form.

Usage: generate_classpath.py <classes-dir> <deps-dir>
"""
import os
import sys


def main():
    classes_dir = sys.argv[1] if len(sys.argv) > 1 else "/mayhem/fuzz-classes"
    deps_dir = sys.argv[2] if len(sys.argv) > 2 else "/mayhem/fuzz-deps"
    entries = [classes_dir]
    if os.path.isdir(deps_dir):
        for name in sorted(os.listdir(deps_dir)):
            if name.endswith(".jar"):
                entries.append(os.path.join(deps_dir, name))
    print(":".join(entries))


if __name__ == "__main__":
    main()
