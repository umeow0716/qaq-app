#!/usr/bin/env bash
set -e

# Setup check for TAT production Android signing.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"

KEYSTORE="$PROJECT_DIR/android/tat.jks"
KEY_PROPERTIES="$PROJECT_DIR/android/key.properties"

if [[ ! -f "$KEYSTORE" ]]; then
  echo "Error: missing android/tat.jks"
  exit 1
fi

if [[ ! -f "$KEY_PROPERTIES" ]]; then
  echo "Error: missing android/key.properties"
  exit 1
fi

echo "Release signing files are ready."
