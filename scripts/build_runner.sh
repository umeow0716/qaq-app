#!/usr/bin/env bash

dart run build_runner build && bash "$(dirname "$0")"/format.sh
