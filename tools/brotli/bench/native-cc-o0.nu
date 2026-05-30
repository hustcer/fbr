#!/usr/bin/env nu

def --wrapped main [...args: string]: nothing -> nothing {
  let filtered = (
    $args
    | each {|arg| if $arg == "-O2" { "-O0" } else { $arg } }
  )
  let result = (^/usr/bin/cc ...$filtered | complete)
  if $result.stdout != "" {
    print --no-newline $result.stdout
  }
  if $result.stderr != "" {
    print --stderr --no-newline $result.stderr
  }
  exit $result.exit_code
}
