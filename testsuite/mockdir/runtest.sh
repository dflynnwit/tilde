#!/bin/bash

die() {
	echo "$*" >&2
	exit 1
}

cd "$(dirname "$0")" || die "could not cd to correct dir"

rm -rf work || die "could not remove stale work dir"
mkdir -p work/dir1 || die "could not create work/dir1"
echo "foo" > work/file1 || die "could not create work/file1"

cd work || die "could not cd to work dir"

# Use the appropriate dynamic linker preload mechanism for the current OS
if [ "$(uname -s)" = "Darwin" ] ; then
	MOCK_LIB=../.libs/libmockdir.dylib
	PRELOAD_VAR="DYLD_INSERT_LIBRARIES"
	DYLD_FORCE_FLAT_NAMESPACE=1
	export DYLD_FORCE_FLAT_NAMESPACE
else
	MOCK_LIB=../.libs/libmockdir.so
	PRELOAD_VAR="LD_PRELOAD"
fi

{
	{ ../mockdir_test | sed -E "s%$PWD%{CWD}%" ; } || die "mockdir_test failed"
	eval "$PRELOAD_VAR=$MOCK_LIB" ../mockdir_test || die "mockdir_test/getcwd failed"
	eval "$PRELOAD_VAR=$MOCK_LIB" MOCK_DIR=.. ../mockdir_test || die "mockdir_test/.. failed"
} > testlog.txt

diff -u ../expected_result.txt testlog.txt || die "test failed"
exit 0

