#!/usr/bin/env bash
set -e

# iOS Patch Script for Xcode 16+ compatibility
# Patches Flutter plugins that have non-modular header issues and iOS 18 incompatibilities
#
# Usage: ./scripts/patch_ios.sh
#
# Run this after `flutter pub get` and before building iOS.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo_step() {
    echo -e "${GREEN}==>${NC} $1"
}

echo_warn() {
    echo -e "${YELLOW}Warning:${NC} $1"
}


# Add privacy manifest to a plugin's iOS directory and podspec
add_privacy_manifest() {
    local plugin_name="$1"
    local plugin_version="$2"
    local plugin_dir="$HOME/.pub-cache/hosted/pub.dev/${plugin_name}-${plugin_version}/ios"

    if [[ ! -d "$plugin_dir" ]]; then
        echo_warn "${plugin_name}-${plugin_version} not found, skipping"
        return
    fi

    echo_step "Adding privacy manifest to ${plugin_name}..."

    local manifest="$plugin_dir/Classes/PrivacyInfo.xcprivacy"
    if [[ ! -f "$manifest" ]]; then
        cat > "$manifest" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>NSPrivacyTrackingDomains</key>
	<array/>
	<key>NSPrivacyAccessedAPITypes</key>
	<array/>
	<key>NSPrivacyCollectedDataTypes</key>
	<array/>
	<key>NSPrivacyTracking</key>
	<false/>
</dict>
</plist>
PLIST
        echo "  Created: PrivacyInfo.xcprivacy"
    fi

    local podspec="$plugin_dir/${plugin_name}.podspec"
    if [[ -f "$podspec" ]] && ! grep -q 'resource_bundles' "$podspec"; then
        sed -i '' "/s\.pod_target_xcconfig/i\\
  s.resource_bundles = {'${plugin_name}_privacy' => ['Classes/PrivacyInfo.xcprivacy']}
" "$podspec"
        echo "  Patched: ${plugin_name}.podspec"
    fi
}

# Patch flutter_inappwebview for iOS 18
patch_flutter_inappwebview() {
    local swift_file="$HOME/.pub-cache/hosted/pub.dev/flutter_inappwebview-5.8.0/ios/Classes/InAppWebView/InAppWebView.swift"

    if [[ ! -f "$swift_file" ]]; then
        echo_warn "flutter_inappwebview-5.8.0 not found, skipping"
        return
    fi

    echo_step "Patching flutter_inappwebview for iOS 18..."

    if grep -q 'public override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil)' "$swift_file"; then
        sed -i '' 's/public override func evaluateJavaScript(_ javaScriptString: String, completionHandler: ((Any?, Error?) -> Void)? = nil)/open override func evaluateJavaScript(_ javaScriptString: String, completionHandler: (@MainActor (Any?, Error?) -> Void)? = nil)/' "$swift_file"
        echo "  Patched: InAppWebView.swift"
    else
        echo "  Already patched or different version"
    fi
}

# Main
patch_flutter_inappwebview
add_privacy_manifest "package_info_plus" "3.1.2"
echo_step "All patches applied!"
