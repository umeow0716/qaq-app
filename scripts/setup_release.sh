#!/usr/bin/env bash
set -euo pipefail

# Validate local Android release signing configuration without assuming a project-specific keystore filename.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
KEY_PROPERTIES="$PROJECT_DIR/android/key.properties"

if [[ ! -f "$KEY_PROPERTIES" ]]; then
  echo "Error: missing android/key.properties"
  exit 1
fi

STORE_FILE="$(sed -n 's/^[[:space:]]*storeFile[[:space:]]*=[[:space:]]*//p' "$KEY_PROPERTIES" | tail -n 1)"
if [[ -z "$STORE_FILE" ]]; then
  echo "Error: android/key.properties does not define storeFile"
  exit 1
fi

if [[ "$STORE_FILE" = /* ]]; then
  KEYSTORE="$STORE_FILE"
else
  KEYSTORE="$PROJECT_DIR/android/app/$STORE_FILE"
fi

if [[ ! -f "$KEYSTORE" ]]; then
  echo "Error: Android release keystore configured by storeFile was not found"
  exit 1
fi

echo "Release signing files are ready."
