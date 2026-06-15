# syntax=docker/dockerfile:1.7
#
# Commit-image Dockerfile for chesslib (Java/Jazzer). Builds ON TOP of the org base image
# (ghcr.io/mayhemheroes/base) — Debian + clang/libFuzzer + the build-contract ENV + the
# non-root `mayhem` identity. The base ships NO Java toolchain, so this image installs, as root
# into shared /opt:
#   * a Temurin JDK 17        -> /opt/jdk   (compile + run)
#   * Apache Maven 3.9        -> /opt/maven (build chesslib + run its JUnit oracle)
#   * Jazzer (v0.30.0)        -> /opt/jazzer (libFuzzer-compatible JVM fuzzing driver + api jar)
# then runs build.sh (mvn package + javac the Jazzer harness) and test.sh (chesslib's JUnit suite).
#
# Build (from the repo root):
#   DOCKER_BUILDKIT=1 docker build -f mayhem/Dockerfile \
#       --build-arg COMMIT=$(git rev-parse HEAD) -t chesslib-commit:test .

FROM ghcr.io/mayhemheroes/base:20260621

ARG COMMIT
ARG REPO_URL
# SOURCE_DATE_EPOCH stays an ARG (never bake as ENV — an empty value breaks clang).
ARG SOURCE_DATE_EPOCH
# Declared for parity; JVM fuzzing instruments bytecode via Jazzer (not $SANITIZER_FLAGS).
ARG SANITIZER_FLAGS

ARG JDK_URL=https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.13%2B11/OpenJDK17U-jdk_x64_linux_hotspot_17.0.13_11.tar.gz
ARG MAVEN_URL=https://archive.apache.org/dist/maven/maven-3/3.9.9/binaries/apache-maven-3.9.9-bin.tar.gz
ARG JAZZER_URL=https://github.com/CodeIntelligenceTesting/jazzer/releases/download/v0.30.0/jazzer-linux-x86-64.tar.gz

ENV JAVA_HOME=/opt/jdk \
    JAZZER_DIR=/opt/jazzer \
    PATH=/opt/jdk/bin:/opt/maven/bin:$PATH

USER root
RUN set -eux; \
    mkdir -p /opt/jdk /opt/maven /opt/jazzer /tmp/dl; \
    cd /tmp/dl; \
    curl -fsSL -o jdk.tar.gz   "$JDK_URL"; \
    curl -fsSL -o maven.tar.gz "$MAVEN_URL"; \
    curl -fsSL -o jazzer.tar.gz "$JAZZER_URL"; \
    tar xzf jdk.tar.gz   -C /opt/jdk   --strip-components=1; \
    tar xzf maven.tar.gz -C /opt/maven --strip-components=1; \
    tar xzf jazzer.tar.gz -C /opt/jazzer; \
    chmod -R a+rX /opt/jdk /opt/maven /opt/jazzer; \
    chmod +x /opt/jazzer/jazzer; \
    cd /; rm -rf /tmp/dl; \
    java -version; mvn -version; test -x /opt/jazzer/jazzer

# Pre-warm the Maven local repo so build.sh / test.sh work offline-ish and faster. Owned by mayhem.
RUN mkdir -p /home/mayhem/.m2 && chown -R 2000:2000 /home/mayhem/.m2

USER mayhem
WORKDIR /mayhem
COPY --chown=2000:2000 . /mayhem

# Build the Jazzer fuzz target (mvn package + javac harness; stages /mayhem/jazzer + classpath).
RUN bash mayhem/build.sh

# Functional oracle: chesslib's own JUnit/Surefire suite. A failing suite fails the image.
RUN if [ -f mayhem/test.sh ]; then bash mayhem/test.sh; else echo "no mayhem/test.sh"; fi

LABEL org.opencontainers.image.source="${REPO_URL}" \
      org.opencontainers.image.revision="${COMMIT}" \
      rlenv.tier="commit" \
      rlenv.source_date_epoch="${SOURCE_DATE_EPOCH}" \
      rlenv.user="mayhem"

USER mayhem
WORKDIR /mayhem
