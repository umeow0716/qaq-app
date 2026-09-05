#!/usr/bin/env bash

dart run intl_utils:generate && bash "$(dirname "$0")"/format.sh
