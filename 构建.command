#!/bin/zsh
set -e
cd "${0:A:h}"
./scripts/build.sh
./scripts/package.sh
