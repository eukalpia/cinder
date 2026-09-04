# List available commands
default:
    @just --list

# Serve the landing page locally (requires Python 3)
landing:
    #!/usr/bin/env bash
    port=$((8000 + RANDOM % 1000))
    echo "Serving landing page at http://localhost:$port"
    cd landing && python3 -m http.server $port

# Run the benchmark suite (pass filter to run specific suites, e.g. just benchmark buffer)
benchmark *ARGS:
    dart run benchmark/benchmark.dart {{ARGS}}

# Run benchmarks and save results as the new baseline
benchmark-save *ARGS:
    dart run benchmark/benchmark.dart --save {{ARGS}}

# Run native, package, formatting, renderer, and publication dry-run checks
check *ARGS:
    dart tool/check.dart {{ARGS}}

# Validate the release. Version/tag publication is documented in doc/release.md.
release: check
    @echo "Validation passed. Follow doc/release.md to publish this exact commit."
