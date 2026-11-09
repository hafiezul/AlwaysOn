#!/bin/bash
# Runs a command and retries it when it fails, waiting 15, 30, then 60 seconds.
# For network steps that fail on transient errors, such as a 504 from GitHub.
#
#   Scripts/retry.sh [-n ATTEMPTS] command [args...]
#
# Only the command's name is logged, never its arguments, so arguments may
# carry tokens. A command that writes to a file must do so itself (wrap it in
# `bash -c '... > file'`), or a failed attempt's output ends up in the file.
set -uo pipefail

attempts=4
if [[ "${1:-}" == "-n" ]]; then
  attempts="$2"
  shift 2
fi
if [[ $# -eq 0 ]]; then
  echo "usage: $0 [-n ATTEMPTS] command [args...]" >&2
  exit 64
fi

delay=15
for ((attempt = 1; ; attempt++)); do
  "$@" && exit 0
  status=$?
  if ((attempt >= attempts)); then
    echo "$1 failed after $attempts attempts (exit $status)" >&2
    exit "$status"
  fi
  echo "$1 failed (exit $status), attempt $attempt of $attempts; retrying in ${delay}s" >&2
  sleep "$delay"
  delay=$((delay * 2))
done
