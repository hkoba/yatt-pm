#!/bin/zsh

set -e

cd $0:h

if ((ARGC)); then
    files=("$@")
else
    files=(*.t(N))
fi

${PERL:-perl} -MTest::Harness -e 'runtests(@ARGV)' $files
