#!/usr/bin/env bash
#
# mayhem/build.sh — build pttbbs' fuzz harnesses (sanitized libs + harnesses) and its upstream
# test programs (normal flags). Runs in the commit image as `mayhem` in /mayhem, offline, and can
# be re-run on a `git clean -ffdX`-ed tree.
set -euo pipefail

# clang rejects SOURCE_DATE_EPOCH='' (empty) — it must be unset or a valid integer.
[ -n "${SOURCE_DATE_EPOCH:-}" ] || unset SOURCE_DATE_EPOCH

: "${SANITIZER_FLAGS=-fsanitize=address,undefined -fno-sanitize-recover=all -fno-omit-frame-pointer}"
: "${DEBUG_FLAGS:=-g -gdwarf-3}"
: "${CC:=clang}" ; : "${CXX:=clang++}" ; : "${LIB_FUZZING_ENGINE:=-fsanitize=fuzzer}"
: "${MAYHEM_JOBS:=$(nproc)}"
: "${COVERAGE_FLAGS=}"
: "${SRC:=/mayhem}"
export SANITIZER_FLAGS DEBUG_FLAGS CC CXX LIB_FUZZING_ENGINE MAYHEM_JOBS COVERAGE_FLAGS

cd "$SRC"

OUT="$SRC"
TMP="${TMPDIR:-/tmp}/pttbbs-build.$$"
mkdir -p "$TMP"
restore_upstream() { :; }  # redefined below while the Go fuzz build has upstream files out
trap 'restore_upstream; rm -rf "$TMP"' EXIT

# upstream's make wraps the compiler in mk/clang_src.py: the sources are Big5, which clang can't read.
CCW="$SRC/mk/clang_src.py"

# --- files upstream's build expects but its .gitignore swallows: recreate them every time ---
cp sample/pttbbs.conf pttbbs.conf
perl util/parsevar.pl < mbbsd/var.c > include/var.h

# Build flags. upstream's own -Werror trips over clang 19's implicit-declaration errors in
# common/bbs/content.c (gettimeofday), so warnings are off and that one diagnostic is demoted.
BASE_MAKE="-DBBSHOME='\"/home/mayhem\"' -I$SRC/include -finput-charset=big5 -fexec-charset=big5 -Wno-everything -Wno-implicit-function-declaration"
BASE_ARR=(-DBBSHOME='"/home/mayhem"' -I"$SRC/include" -finput-charset=big5 -fexec-charset=big5
          -Wno-everything -Wno-implicit-function-declaration)
LIBS=(-L"$SRC/common/bbs" -L"$SRC/common/sys" -L"$SRC/common/osdep" -lcmbbs -lcmsys -losdep -lrt -pthread -lm)

build_libs() { # <extra cflags>
    local d
    for d in osdep sys bbs; do
        make -C "common/$d" clean
        make -C "common/$d" CC="$CCW $CC" CFLAGS="$BASE_MAKE $1" -j"$MAYHEM_JOBS"
    done
}

# 1) Upstream's own tests (mbbsd/test_*.c), normal flags, left in $OUT for mayhem/test.sh.
build_libs "-O2 $COVERAGE_FLAGS"
(
    cd mbbsd
    # shellcheck disable=SC2086
    "$CCW" "$CC" "${BASE_ARR[@]}" -O2 $COVERAGE_FLAGS test_mime.c -o "$OUT/test_mime" "${LIBS[@]}" $COVERAGE_FLAGS
    # shellcheck disable=SC2086
    "$CCW" "$CC" "${BASE_ARR[@]}" -O2 $COVERAGE_FLAGS test_brc.c -o "$OUT/test_brc" "${LIBS[@]}" $COVERAGE_FLAGS
    # shellcheck disable=SC2086
    "$CCW" "$CC" "${BASE_ARR[@]}" -O2 $COVERAGE_FLAGS -DUSE_PFTERM test_pfterm_url.c pfterm.c \
        -o "$OUT/test_pfterm" "${LIBS[@]}" $COVERAGE_FLAGS
)

# 2) Upstream's Go modules (service/, util/viewdir/): their `go test` suites and native Go fuzz
# targets, built against the normal-flag C libs above, exactly as upstream's GO_ENV does
# (service/*/Makefile). The stat Makefile links its tests externally; the other cgo packages need it
# too with clang 19 (runtime/cgo has undefined pthread relocations under the internal linker).
# Modules resolve from the in-image cache first (the Dockerfile bakes it), network only as a fallback.
export GOPROXY="${GOPROXY:-file://$(go env GOMODCACHE)/cache/download,https://proxy.golang.org,direct}"
export GOTOOLCHAIN=local
export CGO_ENABLED=1 CGO_LDFLAGS_ALLOW="-Wl,--gc-sections"
export CGO_CFLAGS="-I$SRC/include -DBBSHOME=\"/home/mayhem\""
export CGO_LDFLAGS="-Wl,--gc-sections -L$SRC/common/bbs -lcmbbs -L$SRC/common/sys -lcmsys -L$SRC/common/osdep -losdep"
go version

# The test binaries, one per package, run by mayhem/test.sh from the package's own directory.
# -mod=readonly: upstream's go.mod is not tidy (direct deps marked indirect) and must not be rewritten.
GOTEST_OUT="$OUT/mayhem-gotest"
rm -rf "$GOTEST_OUT"; mkdir -p "$GOTEST_OUT"
gotest_c() { # <module dir> <package dir, relative to it>
    local name
    name="$(printf '%s' "$1/$2" | sed 's#/\.$##; s#/#_#g')"
    (cd "$SRC/$1" && CC="$CCW $CC" GOFLAGS=-mod=readonly \
        go test -c -ldflags=-linkmode=external -o "$GOTEST_OUT/$name.test" "./$2")
}
GO_TEST_PKGS=(bbs big5uao friend/daemon friend/storage ipc ipc/daemon mail/daemon post post/cmd/post.ctl
              post/config post/importer post/model post/storage search search/cmd/search.ctl
              search/daemon stat/daemon stat/storage svcctl utmp utmp/daemon)
for p in "${GO_TEST_PKGS[@]}"; do gotest_c service "$p"; done
gotest_c util/viewdir .

# Upstream's C client <-> ipc.svc integration test (service/ipc/Makefile `test:`): the daemon, built
# like upstream's `ipc.svc` target, and test/test_ipc_c_client.c against the normal-flag C libs.
# Its checks are assert(), so no -DNDEBUG. mayhem/test.sh starts the daemon and runs the client.
(cd service/ipc && CC="$CCW $CC" GOFLAGS=-mod=readonly \
    go build -ldflags=-linkmode=external -o "$GOTEST_OUT/ipc.svc" .)
# shellcheck disable=SC2086
"$CCW" "$CC" "${BASE_ARR[@]}" -O2 $COVERAGE_FLAGS -Wno-invalid-source-encoding -I"$SRC/common/bbs" \
    service/ipc/test/test_ipc_c_client.c -o "$GOTEST_OUT/test_ipc_c_client" "${LIBS[@]}" $COVERAGE_FLAGS
# The client's Test 5 logs in to the xchatd backend (XCHATD_ADDR, :3838) through ipc.svc's bridge.
# util/xchatd is built in upstream's own SELFTEST mode (util/xchatd.c): accounts come from the
# login line instead of .PASSWDS and the BBS shared memory is not attached, so it runs without an
# installed BBS. Same objects as util/GNUmakefile (util_var.o + xchatd.c + the libs).
# shellcheck disable=SC2086
"$CCW" "$CC" "${BASE_ARR[@]}" -O2 $COVERAGE_FLAGS -DPTTBBS_UTIL -D_BBS_UTIL_C_ -c mbbsd/var.c -o "$TMP/util_var.o"
# shellcheck disable=SC2086
"$CCW" "$CC" "${BASE_ARR[@]}" -O2 $COVERAGE_FLAGS -DPTTBBS_UTIL -DSELFTEST "$TMP/util_var.o" util/xchatd.c \
    -o "$GOTEST_OUT/xchatd" "${LIBS[@]}" $COVERAGE_FLAGS

# Native Go fuzz targets (go-118-fuzz-build -> libFuzzer archive, linked by clang with ASan, as
# OSS-Fuzz's Go path does). Upstream's FuzzParseMail/FuzzANSI are internal tests of
# service/mail/daemon, so they are built in place: go-118-fuzz-build needs its testing shim on the
# module graph (a `go get` into service/go.mod) and rewrites the fuzz test file while it builds.
# Every upstream file it touches is copied out first and put back by restore_upstream, also on error.
ORIG="$TMP/orig"; mkdir -p "$ORIG/mail/daemon"
cp service/go.mod service/go.sum "$ORIG/"
cp service/mail/daemon/*_test.go "$ORIG/mail/daemon/"
restore_upstream() {
    [ -d "$ORIG" ] || return 0
    cp "$ORIG/go.mod" "$ORIG/go.sum" "$SRC/service/"
    cp "$ORIG"/mail/daemon/*_test.go "$SRC/service/mail/daemon/"
    rm -f "$SRC"/service/mail/daemon/*_fuzz.go "$SRC"/service/main.*.go "$SRC"/mayhem/gofuzz/main.*.go
}
GO118_TESTING="github.com/AdamKorcz/go-118-fuzz-build/testing@v0.0.0-20250520111509-a70c2aa677fa"
(cd service && GOFLAGS=-mod=mod go get "$GO118_TESTING")

: "${GO_DEBUG_FLAGS:=-g -gdwarf-3}"
# shellcheck disable=SC2086
$CXX $SANITIZER_FLAGS -c mayhem/lsan_off.cc -o "$TMP/lsan_off.o"
# shellcheck disable=SC2086
$CC $GO_DEBUG_FLAGS -c mayhem/go_runtime_ready.c -o "$TMP/go_runtime_ready.o"
# shellcheck disable=SC2086
$CC $GO_DEBUG_FLAGS -c "$STANDALONE_FUZZ_MAIN" -o "$TMP/standalone_main.o"
go_fuzz() { # <module dir> <package dir> <Fuzz func> <target>
    (cd "$SRC/$1" && CC="$CCW $CC" GOFLAGS=-mod=mod go-118-fuzz-build -o "$TMP/$4.a" -func "$3" "./$2")
    # The init-ordering shim links first (LLVMFuzzerInitialize waits for the Go runtime).
    # shellcheck disable=SC2086
    $CXX $SANITIZER_FLAGS $LIB_FUZZING_ENGINE $GO_DEBUG_FLAGS "$TMP/go_runtime_ready.o" "$TMP/$4.a" \
        "$TMP/lsan_off.o" -o "$OUT/$4" "${LIBS[@]}"
    # shellcheck disable=SC2086
    $CXX $SANITIZER_FLAGS -fsanitize=fuzzer-no-link $GO_DEBUG_FLAGS "$TMP/standalone_main.o" \
        "$TMP/go_runtime_ready.o" "$TMP/$4.a" "$TMP/lsan_off.o" -o "$OUT/$4-standalone" "${LIBS[@]}"
    nm "$OUT/$4" | grep ' T LLVMFuzzerInitialize$' >/dev/null \
        || { echo "build.sh: init-ordering shim missing from $OUT/$4" >&2; exit 1; }
}
go_fuzz service mail/daemon FuzzParseMail fuzz_parse_mail
go_fuzz service mail/daemon FuzzANSI fuzz_ansi
restore_upstream
# Our own Big5-UAO target lives in its own module (mayhem/gofuzz, `replace pttbbs => ../../service`).
go_fuzz mayhem/gofuzz big5uao FuzzBig5UAO fuzz_big5uao

# 3) The C fuzz targets.
# UBSan's function-type check is off: thttp's buffer_read_from_func() calls a (THTTP *, ...) reader
# through an (void *, ...) pointer type, which trips on every call and would end every thttp input.
# Everything else (ASan, the rest of UBSan) stays on and halting.
SAN="$SANITIZER_FLAGS -fno-sanitize=function"

# The project itself, instrumented: sanitizers + SanCov (no-link: the engine is linked per harness).
# shellcheck disable=SC2086
build_libs "-O1 $SAN $DEBUG_FLAGS -fsanitize=fuzzer-no-link"


TARGETS=(fuzz_telnet fuzz_vtkbd fuzz_mime fuzz_charset fuzz_text fuzz_content_verdict fuzz_thttp)
for t in "${TARGETS[@]}"; do
    # shellcheck disable=SC2086
    "$CCW" "$CC" "${BASE_ARR[@]}" -O1 $SAN $DEBUG_FLAGS $LIB_FUZZING_ENGINE \
        "mayhem/$t.c" "$TMP/lsan_off.o" -o "$OUT/$t" "${LIBS[@]}"
    # shellcheck disable=SC2086
    "$CCW" "$CC" "${BASE_ARR[@]}" -O1 $SAN $DEBUG_FLAGS \
        "$STANDALONE_FUZZ_MAIN" "mayhem/$t.c" "$TMP/lsan_off.o" -o "$OUT/$t-standalone" "${LIBS[@]}"
done
