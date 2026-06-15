/*
 * jazzer_launch.c — tiny native ELF launcher for the chesslib Jazzer target.
 *
 * Mayhem (and the fuzz-smoke gate) require the fuzz `cmd` to be a self-contained ELF binary,
 * not a shell script, and may invoke it with extra libFuzzer flags appended (e.g. -runs=...,
 * -max_total_time=..., a corpus dir). The Jazzer driver itself is an ELF but needs --cp and
 * --target_class passed every time. This launcher bakes those in and forwards any extra argv
 * straight through to the real `jazzer` driver, so the target runs identically whether launched
 * bare (smoke) or by Mayhem with its own arguments.
 *
 * It is a pure exec wrapper (replaces itself with jazzer), so it adds no runtime overhead and
 * passes the ELF check.
 *
 * Baked args, and WHY:
 *   --cp / --target_class      the fuzz classpath + Jazzer entry point.
 *   --instrumentation_includes=com.github.bhlangonijr.**
 *                              instrument ONLY chesslib classes (not commons-lang3 / the JDK).
 *                              This is the target we care about, and a smaller instrumentation
 *                              set means a smaller coverage map, lower RSS and a faster JVM boot.
 *   --jvm_args=-Xmx1024m:-XX:+UseSerialGC:-XX:-UsePerfData
 *                              CAP the JVM heap (and trim the per-worker footprint). Without a cap
 *                              the JVM sizes its default heap from the (huge) host RAM and its RSS
 *                              climbs unbounded during a long campaign until it crosses libFuzzer's
 *                              -rss_limit_mb (2048 MB) and libFuzzer SIGKILLs the worker. A SIGKILL
 *                              skips the JVM shutdown hooks, so Jazzer/rules_jni leak the ~5 MB
 *                              native bundle they unpack into java.io.tmpdir on every launch; Mayhem
 *                              then restarts the worker, which unpacks another copy, and the leaked
 *                              temp files fill the 488 MB run tmpfs within seconds. A full disk stops
 *                              libFuzzer/Mayhem from writing the corpus + coverage-merge output, so
 *                              edges_covered came back 0 even though ~19M inputs executed. Capping
 *                              the heap keeps RSS ~650-760 MB (well under 2048), so the worker is
 *                              never rss-killed, temp is cleaned on normal exit, the tmpfs stays
 *                              small and coverage flows. UseSerialGC drops the parallel-GC helper
 *                              threads + their memory; -UsePerfData stops hsperfdata writes.
 *                              These flags are passed via --jvm_args (Jazzer feeds them straight to
 *                              JNI_CreateJavaVM) rather than the JAVA_TOOL_OPTIONS env, because the
 *                              env var makes the JVM print "Picked up JAVA_TOOL_OPTIONS: ..." to
 *                              stderr on every launch, which pollutes the libFuzzer stdout/stderr
 *                              protocol -> Mayhem rejects the target as "output did not match the
 *                              expected libFuzzer format" -> 0 edges. --jvm_args prints no banner.
 */
#include <unistd.h>
#include <stdlib.h>
#include <string.h>

#define JAZZER     "/mayhem/jazzer"
#define CP_ARG     "--cp=/mayhem/fuzz-classes:/mayhem/fuzz-deps/chesslib.jar:/mayhem/fuzz-deps/commons-lang3-3.12.0.jar"
#define TARGET_ARG "--target_class=fuzz_chess_board_loader"
#define INSTR_ARG  "--instrumentation_includes=com.github.bhlangonijr.**"
#define JVM_ARG    "--jvm_args=-Xmx1024m:-XX:+UseSerialGC:-XX:-UsePerfData"

/* Number of baked args placed before any forwarded argv: JAZZER, CP, TARGET, INSTR, JVM. */
#define NBAKED 5

int main(int argc, char **argv) {
    /* argv[0]=launcher, baked args, then any forwarded args, then NULL. */
    int extra = argc - 1;
    int n = NBAKED + extra;
    char **args = (char **)calloc((size_t)(n + 1), sizeof(char *));
    if (!args) {
        return 1;
    }
    int i = 0;
    args[i++] = (char *)JAZZER;
    args[i++] = (char *)CP_ARG;
    args[i++] = (char *)TARGET_ARG;
    args[i++] = (char *)INSTR_ARG;
    args[i++] = (char *)JVM_ARG;
    for (int j = 1; j < argc; j++) {
        args[i++] = argv[j];
    }
    args[i] = NULL;
    execv(JAZZER, args);
    /* execv only returns on error. */
    return 127;
}
