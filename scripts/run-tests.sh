#!/bin/bash

# Change to repo root (parent of scripts/)
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1

# Run just the TypeleastAppTests
swift test --filter "TypeleastAppTests/test" 2>&1 | grep -E "(Test Case|passed|failed|error:|Executed)"