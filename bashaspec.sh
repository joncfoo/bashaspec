#!/bin/bash
# bashaspec - MIT licensed. Copyright 2020 d10n. Feel free to copy around.

# Verbose? true: TAP 12 output; false: dot per test; default false
[[ ${1:-} = -v || ${1:-} = --verbose ]] && verbose=1 || verbose=0

# Runs all the test files
run_test_files() {
  tests=0; fails=0
  while IFS= read -r -d '' cmd; do
    printf '%s\n' "$cmd"
    "$cmd" || ((fails+=1)); ((tests+=1))
  done < <(find . -executable -type f -name '*-spec.sh' -print0)
  echo "$((tests-fails)) of $tests test files passed"
  exit $((fails==0))
}

# Runs all the test functions
# hooks: (before|after)_(all|each)
run_test_functions() {
  temp="$(mktemp)" # Create a temp file for buffering test output
  exec {FD_W}>"$temp" # Open a write file descriptor
  exec {FD_R}<"$temp" # Open a read file descriptor
  rm -- "$temp" # Remove the file. The file descriptors remain open and usable.
  functions="$(compgen -A function | grep '^test_')"
  echo "1..$(printf '%s\n' "$functions" | wc -l)"
  test_index=0; summary_code=0
  run_fn before_all >&$FD_W; bail_if_fail before_all "$?" "$(cat <&$FD_R)"
  while IFS= read -r -d $'\n' fn; do
    status=; fail=; ((test_index += 1))
    run_fn before_each >&$FD_W || { status=$?; fail="$fn before_each"; }
    [[ -n "$fail" ]] || run_fn "$fn" >&$FD_W || { status=$?; fail="$fn"; } # Skip fn if before_each failed
    run_fn after_each >&$FD_W || { _s=$?; [[ -n "$fail" ]] || status="$_s"; fail="$fn after_each"; }
    IFS= read -r -d '' -u $FD_R out
    [[ -z "$fail" ]] || summary_code=1
    echo "${fail:+not }ok $test_index ${fail:-$fn}"
    [[ -z "$fail" ]] || echo "# $fail returned $status"
    [[ -z "$fail" && "$verbose" -lt 2 ]] || [[ -z "$out" ]] || printf %s "$out" | sed 's/^/# /'
  done <<<"$functions"
  run_fn after_all >&$FD_W; bail_if_fail after_all "$?" "$(cat <&$FD_R)"
  return "$summary_code"
}

# Run a function if it exists.
run_fn() { ! declare -F "$1" >/dev/null || "$1"; }

bail_if_fail() { # 1=name 2=code 3=output
  [[ "$2" -eq 0 ]] || {
    echo "Bail out! $1 returned $2"
    [[ -z "$3" ]] || printf '%s\n' "$3" | sed 's/^/# /'
    exit "$2"
  }
}

# If not verbose, format TAP generated by run_test_functions to a dot summary
format() {
  if ((verbose)); then cat; else awk '
    !head&&/1\.\.[0-9]/{sub(/^1../,"");printf "Running %s tests\n",$0}{head=1}
    /^ok/{printf ".";system("");total++;oks++;ok=1;next}
    /^not ok/{printf "x";system("");total++;not_oks++;ok=0;fail_body=0;next}
    /^Bail out!/{fail_lines[fail_line_count++]=$0;not_oks++;ok=0;fail_body=1}
    ok||/^[^#]|^$/{next}
    {sub(/^# /,"")}
    fail_body{sub(/^/,"  ")}
    {fail_lines[fail_line_count++]=$0;fail_body=1}
    END{
      printf "\n%d of %d tests passed\n",oks,total
      if(fail_line_count){printf "%d failures:\n",not_oks}
      for(i=0;i<fail_line_count;i++){printf "  %s\n",fail_lines[i]}
      if(not_oks){exit 1}
    }'
  fi
}

if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  run_test_files
else
  trap 'run_test_functions | format; exit $?' EXIT
fi
