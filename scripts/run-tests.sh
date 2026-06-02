#!/bin/bash
set -e

echo "----------------------------------------"
echo "Chobi Command Line CI Test Suite"
echo "----------------------------------------"

# Ensure we are in the repository root directory
cd "$(dirname "$0")/.."

# Compile the stress test suite
echo "Compiling swift files with optimizations (-O)..."
swiftc -O -sdk $(xcrun --show-sdk-path --sdk macosx) -enable-bare-slash-regex \
    Chobi/Core/Models.swift \
    Chobi/Core/AnalysisEngine.swift \
    Chobi/Core/DeterministicReviewPolicy.swift \
    Tests/CIStressTest.swift \
    -o Tests/CIStressTestExecutable

# Execute the test executable
echo "Executing stress test executable..."
./Tests/CIStressTestExecutable

# Clean up
rm -f Tests/CIStressTestExecutable
echo "CI tests completed cleanly and successfully!"
