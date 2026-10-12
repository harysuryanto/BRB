#!/usr/bin/env bash
#
# build-dmg.sh
# Packages BRB into a polished drag-and-drop macOS DMG installer.
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_PATH="${REPO_ROOT}/build/Release/BRB.app"
VERSION=$(grep -m1 "MARKETING_VERSION = " "${REPO_ROOT}/BRB.xcodeproj/project.pbxproj" | tr -d ' ;' | cut -d'=' -f2)
OUTPUT_DMG="${REPO_ROOT}/BRB-v${VERSION}.dmg"
BG_IMAGE="${REPO_ROOT}/scripts/assets/dmg-background.tiff"

REBUILD=0

for arg in "$@"; do
    case "$arg" in
        --rebuild)
            REBUILD=1
            ;;
        --help|-h)
            echo "Usage: $0 [--rebuild]"
            echo "  --rebuild   Force rebuild the Release app before generating DMG"
            exit 0
            ;;
        *)
            echo "Unknown argument: $arg"
            echo "Usage: $0 [--rebuild]"
            exit 1
            ;;
    esac
done

# 1. Check dependencies
if ! command -v create-dmg >/dev/null 2>&1; then
    echo "❌ Error: 'create-dmg' is not installed."
    echo "Install it using Homebrew:"
    echo "    brew install create-dmg"
    exit 1
fi

# 2. Ensure background image exists
if [[ ! -f "$BG_IMAGE" ]]; then
    echo "🎨 Generating Light Theme DMG background..."
    swift "${REPO_ROOT}/scripts/generate-dmg-background.swift" "${REPO_ROOT}"
fi

# 3. Build Release if needed
if [[ $REBUILD -eq 1 ]] || [[ ! -d "$APP_PATH" ]]; then
    echo "🔨 Building BRB in Release configuration..."
    xcodebuild -project "${REPO_ROOT}/BRB.xcodeproj" \
        -scheme BRB \
        -configuration Release \
        -destination 'platform=macOS' \
        build

    # Copy from DerivedData if not present in build/Release
    DERIVED_APP="$(find ~/Library/Developer/Xcode/DerivedData -name "BRB.app" -path "*/Release/*" 2>/dev/null | head -n 1 || true)"
    if [[ -d "$DERIVED_APP" ]]; then
        mkdir -p "${REPO_ROOT}/build/Release"
        cp -R "$DERIVED_APP" "${REPO_ROOT}/build/Release/"
    fi
fi

if [[ ! -d "$APP_PATH" ]]; then
    echo "❌ Error: BRB.app could not be found at ${APP_PATH}"
    exit 1
fi
# Resolve final bundle version if Info.plist is present
if [[ -f "${APP_PATH}/Contents/Info.plist" ]]; then
    VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "${APP_PATH}/Contents/Info.plist" 2>/dev/null || echo "$VERSION")
    OUTPUT_DMG="${REPO_ROOT}/BRB-v${VERSION}.dmg"
fi


# 4. Ad-hoc codesign for clean portable distribution
echo "✍️  Ad-hoc signing BRB.app for portable distribution..."
codesign --force --deep -s - "$APP_PATH"

# 5. Prepare staging directory
STAGE_DIR="$(mktemp -d /tmp/brb-dmg-XXXXXX)"
cleanup() {
    rm -rf "$STAGE_DIR"
}
trap cleanup EXIT

echo "📦 Staging application..."
cp -R "$APP_PATH" "${STAGE_DIR}/"

# 6. Build DMG with create-dmg
echo "💿 Generating drag-and-drop DMG with light theme background..."
rm -f "$OUTPUT_DMG"

CREATE_DMG_ARGS=(
    --volname "BRB"
    --window-pos 200 120
    --window-size 600 420
    --icon-size 120
    --icon "BRB.app" 150 180
    --hide-extension "BRB.app"
    --app-drop-link 450 180
    --overwrite
)

if [[ -f "$BG_IMAGE" ]]; then
    CREATE_DMG_ARGS+=(--background "$BG_IMAGE")
fi

create-dmg "${CREATE_DMG_ARGS[@]}" "$OUTPUT_DMG" "$STAGE_DIR"

echo "✅ Successfully created DMG:"
ls -lh "$OUTPUT_DMG"
