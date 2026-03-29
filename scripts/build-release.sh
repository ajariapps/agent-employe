#!/bin/bash
# Build script for cross-platform release binaries

set -e

VERSION=${VERSION:-$(git describe --tags --always 2>/dev/null || echo "dev")}
BUILD_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
PROFILE=${PROFILE:-release}

echo "Building Employee Monitoring Agent v$VERSION ($BUILD_TIME)"

# Targets to build
TARGETS=(
    "x86_64-unknown-linux-gnu"
    "x86_64-unknown-linux-musl"
    "aarch64-unknown-linux-gnu"
    "x86_64-pc-windows-gnu"
    "x86_64-apple-darwin"
    "aarch64-apple-darwin"
)

# Create dist directory
mkdir -p dist

for target in "${TARGETS[@]}"; do
    echo ""
    echo "=== Building for $target ==="

    # Add target if needed
    rustup target add "$target" 2>/dev/null || true

    # Build
    cargo build --profile "$PROFILE" --target "$target"

    # Determine binary extension
    case "$target" in
        *-windows-*)
            EXT=".exe"
            ;;
        *)
            EXT=""
            ;;
    esac

    # Copy binary
    BIN_NAME="agent${EXT}"
    SOURCE="target/$target/$PROFILE/$BIN_NAME"
    OUTPUT="dist/agent-v${VERSION}-${target}${EXT}"

    if [ -f "$SOURCE" ]; then
        cp "$SOURCE" "$OUTPUT"
        echo "Built: $OUTPUT"

        # Create archive
        case "$target" in
            *-linux-*|*-darwin-*)
                tar czf "dist/agent-v${VERSION}-${target}.tar.gz" \
                    -C dist "$(basename $OUTPUT)" \
                    config.example.toml README.md 2>/dev/null || true
                echo "Archive: dist/agent-v${VERSION}-${target}.tar.gz"
                ;;
            *-windows-*)
                zip -q "dist/agent-v${VERSION}-${target}.zip" \
                    "$(basename $OUTPUT)" \
                    config.example.toml README.md 2>/dev/null || true
                echo "Archive: dist/agent-v${VERSION}-${target}.zip"
                ;;
        esac

        # Print binary size
        SIZE=$(du -h "$OUTPUT" | cut -f1)
        echo "Size: $SIZE"
    else
        echo "Warning: Binary not found at $SOURCE"
    fi
done

echo ""
echo "=== Build Summary ==="
echo "Version: $VERSION"
echo "Profile: $PROFILE"
ls -lh dist/ | grep -E '\.(exe|tar\.gz|zip)$' || true

echo ""
echo "Build complete!"
