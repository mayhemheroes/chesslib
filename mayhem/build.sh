#!/bin/bash
# build.sh — build the chesslib Jazzer fuzz target.
#
# Runs as the non-root `mayhem` user inside the commit image. The Dockerfile (root) already
# installed a JDK (/opt/jdk), Maven (/opt/maven), and Jazzer (/opt/jazzer) and put them on PATH.
#
# Steps:
#   1. mvn package         -> the chesslib library jar (target/chesslib-*.jar)
#   2. mvn dependency:copy-dependencies -> runtime deps (commons-lang3) under target/dependency
#   3. javac the harness against the lib jar + jazzer api jar
#   4. assemble a flat classpath + copy the `jazzer` driver into /mayhem so the Mayhemfile cmd's
#      first token is a single ELF (jazzer) followed by --cp/--target_class args.
set -eux

SRC="${SRC:-/mayhem}"
cd "$SRC"

export JAVA_HOME="${JAVA_HOME:-/opt/jdk}"
export PATH="$JAVA_HOME/bin:/opt/maven/bin:$PATH"
JAZZER_DIR="${JAZZER_DIR:-/opt/jazzer}"

# $DEBUG_FLAGS threads DWARF < 4 debug info onto every native ELF we emit (SPEC 6.2 item 10):
# clang-19's plain -g emits DWARF-5, which Mayhem's triage cannot read. The Mayhem target here is
# a native launcher (jazzer_launch.c), so it MUST carry DWARF-3 symbols like any C/C++ target.
# SANITIZER_FLAGS is accepted for the build contract, but the Mayhem target here is a Jazzer
# (JVM-bytecode) fuzzer: coverage + sanitization come from Jazzer instrumentation, not clang
# $SANITIZER_FLAGS. The native launcher merely execs the jazzer driver (exec replaces the image,
# so ASan preloaded into the shim would never reach the JVM), so we thread it for the contract but
# do NOT apply it to the shim. `=` (not `:=`) so `--build-arg SANITIZER_FLAGS=` disables it cleanly.
: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
export SANITIZER_FLAGS
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
export DEBUG_FLAGS

# Air-gapped re-run (SPEC 6.2 item 9 / 6.5): the FIRST build (inside docker build, network ON)
# populates ~/.m2 with every plugin + dependency these goals need; that cache is baked into the
# image layer. Once warm, force Maven OFFLINE (-o) so the verify/PATCH re-run works under
# --network none (no maven-metadata / SNAPSHOT lookups). commons-lang3 is chesslib's declared
# runtime dep, so its presence is the "cache is warm" marker.
MVN_OFFLINE=""
if [ -d "$HOME/.m2/repository/org/apache/commons/commons-lang3" ]; then MVN_OFFLINE="-o"; fi

java -version
mvn -version

# Build the library jar + copy runtime dependencies. Skip tests here (test.sh runs them as the oracle).
mvn $MVN_OFFLINE -q -B -DskipTests package
mvn $MVN_OFFLINE -q -B org.apache.maven.plugins:maven-dependency-plugin:3.6.1:copy-dependencies -DincludeScope=runtime

# Stage all classpath jars (library + runtime deps + jazzer api) under /mayhem/fuzz-deps.
DEPS="$SRC/fuzz-deps"
rm -rf "$DEPS"
mkdir -p "$DEPS"
find "$SRC/target" -maxdepth 1 -name 'chesslib-*.jar' ! -name '*-sources.jar' ! -name '*-javadoc.jar' \
    -exec cp {} "$DEPS/chesslib.jar" \;
cp "$SRC"/target/dependency/*.jar "$DEPS/" 2>/dev/null || true
cp "$JAZZER_DIR/jazzer_standalone.jar" "$DEPS/jazzer_standalone.jar"

# Compile the harness against the library + Jazzer API.
HARNESS_OUT="$SRC/fuzz-classes"
rm -rf "$HARNESS_OUT"
mkdir -p "$HARNESS_OUT"
javac -encoding UTF-8 -cp "$DEPS/*" -d "$HARNESS_OUT" mayhem/src/fuzz_chess_board_loader.java

# Record the resolved classpath for reference/debugging (Mayhemfile uses the wildcard form).
python3 mayhem/fuzz/generate_classpath.py "$HARNESS_OUT" "$DEPS" > "$SRC/fuzz-classpath.txt"
cat "$SRC/fuzz-classpath.txt"

# Put the jazzer driver ELF + its standalone agent jar at stable paths. The driver auto-discovers
# jazzer_standalone.jar when it sits next to the `jazzer` binary, so no --agent_path is needed.
cp "$JAZZER_DIR/jazzer" "$SRC/jazzer"
cp "$JAZZER_DIR/jazzer_standalone.jar" "$SRC/jazzer_standalone.jar"
chmod +x "$SRC/jazzer"

# Compile the native ELF launcher that execs jazzer with the baked --cp/--target_class and forwards
# any extra args. This is the Mayhem `cmd` target: a self-contained ELF that iterates when run bare
# (fuzz-smoke) or with Mayhem's own libFuzzer arguments. Built with the base image's clang ($CC).
"${CC:-clang}" $DEBUG_FLAGS -O2 -o "$SRC/fuzz_chess_board_loader" mayhem/src/jazzer_launch.c
chmod +x "$SRC/fuzz_chess_board_loader"

echo "BUILD OK."
ls -la "$SRC/jazzer" "$SRC/jazzer_standalone.jar" "$SRC/fuzz_chess_board_loader" "$HARNESS_OUT" "$DEPS"
