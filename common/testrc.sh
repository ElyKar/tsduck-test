#!/bin/bash
# ------------------------------------------------------------------------------
# This file shall be source'd by all test scripts.
# It parses the common command line options and defines variables and functions.
# ------------------------------------------------------------------------------

# Build script name from caller's name.
SCRIPT=$(basename ${BASH_SOURCE[1]} .sh)

# Root directory of test repository and subdirs.
COMMONDIR=$(cd $(dirname ${BASH_SOURCE[0]}); pwd)
ROOTDIR=$(cd "$COMMONDIR/.."; pwd)
TESTSDIR="$ROOTDIR/tests"
INDIR="$ROOTDIR/input"
REFDIR="$ROOTDIR/reference"
TMPDIR="$ROOTDIR/tmp"

# Root directory of TSDuck repository, supposed to be cloned at same level.
TSDUCKDIR=$(cd "$ROOTDIR/.."; pwd)/tsduck

# Default values for command line options.
DEVEL=false
TESTINIT=false
VERBOSE=false

# Output line prefixes.
PRPASS="----"
PRFAIL="XXXX"
PRVOID="    "

# Functions to report messages.
error() { echo >&2 "$SCRIPT: $*"; exit 1; }
info()  { echo >&2 "$*"; }
trace() { $VERBOSE && info "$PRVOID  $*"; }
usage() { echo >&2 "invalid command, try \"$SCRIPT --help\""; exit 1; }

# Use GNU variants of sed and grep when available.
[[ -n "$(which gsed 2>/dev/null)" ]] && sed() { gsed "$@"; }
[[ -n "$(which ggrep 2>/dev/null)" ]] && grep() { ggrep "$@"; }

# Prefix of a file path (remove extension).
prefix() { sed -e 's/\.[^\.]*$//' <<<$1; }

# Detect various types of UNIX-like environments on UNIX
case $(uname -s | tr A-Z a-z) in
    cygwin*|msys*|mingw*)
        WINDOWS=true
        TSDUCKBIN_ROOT=$TSDUCKDIR/build/msvc2017
        TSDUCKBIN_RELEASE=Release-x64
        TSDUCKBIN_DEBUG=Debug-x64
        EXE=.exe
        ;;
    *)
        WINDOWS=false
        ARCH=$(uname -m | sed -e 's/i.86/i386/')
        TSDUCKBIN_ROOT=$TSDUCKDIR/src/tstools
        TSDUCKBIN_RELEASE=release-$ARCH
        TSDUCKBIN_DEBUG=debug-$ARCH
        EXE=
        ;;
esac

# Display help text
showhelp()
{
    cat >&2 <<EOF

Usage: $SCRIPT [options]

Common test options:

  --dev
      Use development versions of TSDuck as compiled in the Git repository in
      $TSDUCKBIN_ROOT/$TSDUCKBIN_RELEASE

  --debug
      Use debug versions of TSDuck as compiled in the Git repository in
      $TSDUCKBIN_ROOT/$TSDUCKBIN_DEBUG

  --help
      Display this help text.

  --init
      Create initial reference output files. This should be done at least once
      for each test. The reference files must be checked manually to ensure
      that they are correct. They will be later used as reference for the test.

  -v
  --verbose
      Display verbose information.

EOF
    exit 1
}

# Decode command line options.
while [[ $# -gt 0 ]]; do
    case "$1" in
        --dev*)
            DEVEL=true
            TSDUCKBIN=$TSDUCKBIN_ROOT/$TSDUCKBIN_RELEASE
            ;;
        --debug*)
            DEVEL=true
            TSDUCKBIN=$TSDUCKBIN_ROOT/$TSDUCKBIN_DEBUG
            ;;
        --help)
            showhelp
            ;;
        --init*)
            TESTINIT=true
            ;;
        -v|--verbose)
            VERBOSE=true
            ;;
        *)
            usage
            ;;
    esac
    shift
done

# Make sure the temporary directory (for test output) exists.
mkdir -p "$TMPDIR"

# Locate the TSDuck executables
if $DEVEL; then
    # Development mode, check that the bin directory exists.
    [[ -d "$TSDUCKBIN" ]] || error "not found: $TSDUCKBIN"

    # Build the path for a TSDuck command.
    tspath() { echo "$TSDUCKBIN/$1$EXE"; }

    # With make (not MSVC), we need to set some environment variables.
    if ! $WINDOWS; then
        [[ -s "$TSDUCKBIN/setenv.sh" ]] || error "not found: $TSDUCKBIN/setenv.sh"
        source "$TSDUCKBIN/setenv.sh"
    fi
else
    # Build the path for a TSDuck command (use the installed product).
    tspath() { echo "$1$EXE"; }
fi

# Build the native path of a file, required for TSDuck command line arguments.
if $WINDOWS; then
    fpath() { cygpath -w "$1"; }
else
    fpath() { echo "$1"; }
fi

# Number of lines in a file.
linecount() { wc -l "$1" | awk '{print $1}'; }

# The output files are created in the reference area with --init.
$TESTINIT && OUTDIR="$REFDIR" || OUTDIR="$TMPDIR"

# Log a test success or failure.
PASSED="$TMPDIR/.passed"
FAILED="$TMPDIR/.failed"
pass() { info "$PRPASS  $SCRIPT: $*"; echo "$SCRIPT: $*" >>$PASSED; }
fail() { info "$PRFAIL  $SCRIPT: $*"; echo "$SCRIPT: $*" >>$FAILED; }

# Check if an argument matches a string. Print "true" or "false".
# Syntax: test_arg string args....
test_arg() {
    local test="$1"
    local arg
    shift
    for arg in "$@"; do
        if [[ "$arg" == "$test" ]]; then
            echo true
            return 0
        fi
    done
    echo false
    return 1
}

# Initializes a test run, reset passed and failed tests.
test_start() {
    rm -f "$PASSED" "$FAILED"
    touch "$PASSED" "$FAILED"
}

# Exit test script, report failed or passed tests.
test_exit() {
    NPASSED=$(linecount "$PASSED")
    NFAILED=$(linecount "$FAILED")
    if $TESTINIT; then
        info "$PRPASS  Tests initialization completed"
    elif [[ $NFAILED -eq 0 ]]; then
        info "$PRPASS  ALL $NPASSED tests passed"
    else
        info "$PRFAIL  $NFAILED tests FAILED, $NPASSED tests passed, review failed tests in $FAILED"
    fi
    exit $NFAILED
}

# Cleanup temporary output file matching a wildcard.
# Syntax: test_cleanup test-file-wildcard
test_cleanup() {
    [[ -n "$1" ]] && rm -rf "$OUTDIR"/$1
}

# Check a temporary text file in 'tmp' against a reference file in 'reference'.
# Do nothing with --init since we are creating the reference files.
# Syntax: test_text test-file [-s]
# Option: -s: silent in case of success
test_text() {
    local file=$1
    local silent=$(test_arg -s "$@")

    # Remove all reference to $INDIR and $OUTDIR in case this is a log file.
    in=$(fpath "$INDIR" | sed -e 's|\\|\\\\|g' )
    out=$(fpath "$OUTDIR" | sed -e 's|\\|\\\\|g' )
    sed -i -e "s|$in[/\\\\]*||g" -e "s|$out[/\\\\]*||g" "$OUTDIR/$file"

    # Do not compare if this is test initialization.
    $TESTINIT && return 0

    # Compare the files.
    if [[ ! -r "$REFDIR/$file" ]]; then
        fail "Reference output $REFDIR/$file missing"
        return 1
    elif diff --strip-trailing-cr "$REFDIR/$file" "$TMPDIR/$file" >$TMPDIR/$file.diff; then
        rm -f "$TMPDIR/$file.diff"
        $silent || pass "Test $file passed"
        return 0
    else
        fail "Test $file FAILED, check $TMPDIR/$file.diff"
        return 1
    fi
}

# Check a temporary binary file in 'tmp' against a reference file in 'reference'.
# Do nothing with --init since we are creating the reference files.
# Syntax: test_bin test-file [-s]
# Option: -s: silent in case of success
test_bin() {
    local file=$1
    local silent=$(test_arg -s "$@")

    # Do not compare if this is test initialization.
    $TESTINIT && return 0

    # Compare the files.
    if [[ ! -r "$REFDIR/$file" ]]; then
        fail "Reference output $REFDIR/$file missing"
        return 1
    elif cmp "$REFDIR/$file" "$TMPDIR/$file" >$TMPDIR/$file.diff; then
        rm -f "$TMPDIR/$file.diff"
        $silent || pass "Test $file passed"
        return 0
    else
        [[ $(linecount "$TMPDIR/$file.diff") -eq 1 ]] && details=$(cat "$TMPDIR/$file.diff") || details="see $TMPDIR/$file.diff"
        fail "Test $file FAILED, $details"
        return 1
    fi
}
