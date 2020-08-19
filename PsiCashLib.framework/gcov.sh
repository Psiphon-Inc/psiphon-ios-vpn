#!/bin/bash
if [ $(which llvm-cov) ]; then
  exec llvm-cov gcov "$@"
else
  exec gcov "$@"
fi
