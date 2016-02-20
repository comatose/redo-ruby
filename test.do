#!/usr/bin/env sh
echo "hello test?" > $3
echo $REDO_DEPS_PATH
echo $REDO_CALL_DEPTH
./redo-ifchange test.a test0.a
