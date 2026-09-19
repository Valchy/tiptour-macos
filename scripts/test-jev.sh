#!/bin/bash
# Run the pure JEV tests without building, signing, or launching TipTour.
set -euo pipefail
project_dir="$(cd "$(dirname "$0")/.." && pwd)"
test_dir="$(mktemp -d "${TMPDIR:-/tmp}/tiptour-jev-tests.XXXXXX")"
trap 'rm -rf "$test_dir"' EXIT
mkdir -p "$test_dir/Sources/JevCore" "$test_dir/Tests/JevCoreTests"
cat > "$test_dir/Package.swift" <<'SWIFT'
// swift-tools-version: 6.0
import PackageDescription
let package = Package(
    name: "JevCore", platforms: [.macOS(.v14)],
    targets: [.target(name: "JevCore"), .testTarget(name: "JevCoreTests", dependencies: ["JevCore"])],
    swiftLanguageModes: [.v5]
)
SWIFT
cp "$project_dir/TipTour/Jev/JevClient.swift" "$project_dir/TipTour/Jev/JevGrounding.swift" \
   "$project_dir/TipTour/Core/TipTourMode.swift" "$project_dir/TipTour/Utilities/KeychainStore.swift" "$test_dir/Sources/JevCore/"
sed 's/@testable import TipTour/@testable import JevCore/' \
    "$project_dir/TipTourTests/JevTests.swift" > "$test_dir/Tests/JevCoreTests/JevTests.swift"
swift test --package-path "$test_dir"
