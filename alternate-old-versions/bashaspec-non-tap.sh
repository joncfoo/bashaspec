#!/bin/bash
# bashaspec - MIT licensed. Copyright 2020 d10n. Feel free to copy around.
# Non-TAP version with simpler but less featureful implementation.

# Verbose? true: line per test; false: dot per test; default false
[[ ${1:-} = -v || ${1:-} = --verbose ]] && verbose=1 || verbose=0

# Runs all the test files
run_test_files() {
  code=0
  while IFS= read -r -d '' cmd; do
    printf '%s\n' "$cmd"
    if ((verbose)); then "$cmd" -v; else "$cmd"; fi || code=1
  done < <(find . -perm -a=x -type f -name '*-spec.sh' -print0)
  exit "$code"
}

# Runs all the test functions
# hooks: (before|after)_(all|each)
run_test_functions() {
  temp="$(mktemp)" # Create a temp file for buffering test output
  test_w=3; exec 3>"$temp" # Open a write file descriptor
  test_r=4; exec 4<"$temp" # Open a read file descriptor
  rm -- "$temp" # Remove the file. The file descriptors remain open and usable.
  functions="$(compgen -A function | grep '^test_')"
  fails=()
  run_fn before_all || bail
  while IFS= read -r fn; do
    run_fn before_each || continue
    run_fn "$fn" print || true
    run_fn after_each || continue
  done <<<"$functions"
  run_fn after_all || bail
  print_failures
}

# Run a function if it exists.
# Buffer its output, and if the function failed, save the output
run_fn() {
  declare -F "$1" >/dev/null || return 0
  [[ "${2:-}" = print ]] && print=1 || print=0
  if ((print && verbose)); then printf '%s ' "$1"; fi
  status=0
  "$1" >&$test_w || status=$?
  IFS= read -r -d '' -u $test_r out || true
  if [[ $status -ne 0 ]]; then
    if ((print)); then ((verbose)) && echo 'fail' || printf x; fi
    fails+=("$1 returned $status")
    if [[ -n "$out" ]]; then fails+=("$(printf %s "$out" | sed 's/^/  /')"); fi
  else
    if ((print)); then ((verbose)) && echo 'ok' || printf .; fi
  fi
  return $status
}

print_failures() {
  ((verbose)) || echo
  [[ "${#fails[@]}" -eq 0 ]] && echo 'All ok' && return
  echo 'Failures:'
  for fail in "${fails[@]}"; do
    printf '%s\n' "$fail" | sed 's/^/  /'
  done
  return 1
}

bail() {
  print_failures
  exit 1
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  run_test_files
else
  run_test_functions
fi
