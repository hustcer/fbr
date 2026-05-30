#!/usr/bin/env nu

const lock_dir = "tools/brotli/.size-lock"
const temp_dirs = [
  "src/fbr_size_decode_main"
  "src/fbr_size_encode_main"
  "src/fbr_size_full_main"
]

def process-alive [pid: int]: nothing -> bool {
  let probe = (^ps -p ($pid | into string) | complete)
  $probe.exit_code == 0
}

def lock-pid-path []: nothing -> string {
  $lock_dir | path join "pid"
}

def stale-lock []: nothing -> bool {
  let pid_path = lock-pid-path
  if not ($pid_path | path exists) {
    true
  } else {
    try {
      let pid = (open --raw $pid_path | str trim | into int)
      not (process-alive $pid)
    } catch {
      true
    }
  }
}

def write-lock-pid []: nothing -> nothing {
  $nu.pid | into string | save --force (lock-pid-path)
}

def acquire-lock []: nothing -> nothing {
  let made = (^mkdir $lock_dir | complete)
  if $made.exit_code != 0 {
    if (stale-lock) {
      rm --force --recursive $lock_dir
      let retry = (^mkdir $lock_dir | complete)
      if $retry.exit_code == 0 {
        write-lock-pid
      } else {
        print --stderr "Another fbr size verification is running; retry after it finishes."
        exit 1
      }
    } else {
      let pid_path = lock-pid-path
      let owner = if ($pid_path | path exists) { open --raw $pid_path | str trim } else { "unknown" }
      print --stderr $"Another fbr size verification is running \(pid: ($owner)\); retry after it finishes."
      exit 1
    }
  } else {
    write-lock-pid
  }
}

def release-lock []: nothing -> nothing {
  rm --force --recursive $lock_dir
}

def cleanup-temp-packages []: nothing -> nothing {
  for dir in $temp_dirs {
    rm --force --recursive $dir
  }
}

def save-lines [path: string, lines: list<string>]: nothing -> nothing {
  $lines | str join (char newline) | save --force $path
}

def write-package [dir: string, import_path: string]: nothing -> nothing {
  mkdir $dir
  save-lines ($dir | path join "moon.pkg") [
    "import {"
    $"  \"($import_path)\""
    "}"
    ""
    "options("
    "  \"is-main\": true,"
    ")"
    ""
  ]
}

def write-decode-main []: nothing -> nothing {
  let dir = "src/fbr_size_decode_main"
  write-package $dir "hustcer/fbr/decode"
  save-lines ($dir | path join "main.mbt") [
    "fn main {"
    "  let output = @decode.unbrotli_sync([0x06]) catch { _ => FixedArray::make(0, b'\\x00') }"
    "  println(output.length())"
    "}"
    ""
  ]
}

def write-encode-main []: nothing -> nothing {
  let dir = "src/fbr_size_encode_main"
  write-package $dir "hustcer/fbr/encode"
  save-lines ($dir | path join "main.mbt") [
    "fn main {"
    "  let input : FixedArray[Byte] = [1, 2, 3, 4, 5]"
    "  let output = @encode.brotli_sync(input) catch { _ => FixedArray::make(0, b'\\x00') }"
    "  println(output.length())"
    "}"
    ""
  ]
}

def write-full-main []: nothing -> nothing {
  let dir = "src/fbr_size_full_main"
  write-package $dir "hustcer/fbr"
  save-lines ($dir | path join "main.mbt") [
    "fn main {"
    "  let input : FixedArray[Byte] = [1, 2, 3, 4, 5]"
    "  let compressed = @fbr.brotli_sync(input) catch { _ => FixedArray::make(0, b'\\x00') }"
    "  let output = @fbr.unbrotli_sync(compressed) catch { _ => FixedArray::make(0, b'\\x00') }"
    "  println(output.length())"
    "}"
    ""
  ]
}

def write-temp-packages []: nothing -> nothing {
  cleanup-temp-packages
  write-decode-main
  write-encode-main
  write-full-main
}

def artifact-path [target: string, package: string]: nothing -> string {
  let dir = (["_build" $target "release" "build" $package] | path join)
  let ext = if $target == "js" { "js" } else if $target == "wasm-gc" { "wasm" } else { "" }
  let exact = if $ext == "" { "" } else { $dir | path join $"($package).($ext)" }
  if $exact != "" and ($exact | path exists) {
    $exact
  } else {
    let candidates = (glob ($dir | path join $"($package).*") | where {|path| not ($path | str ends-with ".mi") })
    if ($candidates | length) == 0 {
      print --stderr $"Missing release artifact for ($package) under ($dir)"
      exit 1
    }
    $candidates | first
  }
}

def file-size [path: string]: nothing -> int {
  ls $path | get size | first | into int
}

def marker-hits [content: string, markers: list<string>]: nothing -> list<string> {
  $markers | where {|marker| $content | str contains $marker }
}

def scan-js-artifact [artifact: string, case_name: string]: nothing -> record {
  let content = open --raw $artifact
  let forbidden = if $case_name == "decode-only" {
    [
      "hustcer3fbr6encode"
      "BrotliBitWriter"
      "BrotliHash"
      "BrotliEncodeCommand"
      "build__simple__lz77"
      "bounded__shortest"
    ]
  } else if $case_name == "encode-only" {
    [
      "hustcer3fbr6decode"
      "BrotliBitReader"
      "BrotliDecoderState"
      "BrotliOutputBuilder"
      "decode__metablock"
      "read__huffman"
    ]
  } else {
    []
  }
  let required = if $case_name == "full" {
    ["hustcer3fbr6decode" "hustcer3fbr6encode"]
  } else {
    []
  }
  let forbidden_found = marker-hits $content $forbidden
  let required_found = marker-hits $content $required
  {
    forbidden_found: $forbidden_found
    required_found: $required_found
    symbol_ok: (($forbidden_found | length) == 0 and ($required_found | length) == ($required | length))
  }
}

def build-fixtures [target: string]: nothing -> nothing {
  let result = (
    ^moon build
      src/fbr_size_decode_main
      src/fbr_size_encode_main
      src/fbr_size_full_main
      --release
      --target $target
    | complete
  )
  if $result.exit_code != 0 {
    print --stderr $result.stdout
    print --stderr $result.stderr
    cleanup-temp-packages
    release-lock
    exit $result.exit_code
  }
}

def collect-row [target: string, case_name: string, package: string]: nothing -> record {
  let artifact = artifact-path $target $package
  let scan = if $target == "js" {
    scan-js-artifact $artifact $case_name
  } else {
    {forbidden_found: [], required_found: [], symbol_ok: true}
  }
  {
    target: $target
    case: $case_name
    package: $package
    bytes: (file-size $artifact)
    ok: $scan.symbol_ok
    artifact: $artifact
    symbol_checked: ($target == "js")
    forbidden_found: $scan.forbidden_found
    required_found: $scan.required_found
  }
}

def run-target [target: string]: nothing -> list<record> {
  build-fixtures $target
  [
    (collect-row $target "decode-only" "fbr_size_decode_main")
    (collect-row $target "encode-only" "fbr_size_encode_main")
    (collect-row $target "full" "fbr_size_full_main")
  ]
}

def parse-targets [targets: string]: nothing -> list<string> {
  $targets | split row "," | each {|target| $target | str trim } | where {|target| $target != "" }
}

def main [
  --targets: string = "js" # Comma-separated MoonBit targets. JS enables symbol scanning.
  --json                   # Emit machine-readable JSON.
]: nothing -> nothing {
  acquire-lock
  write-temp-packages

  mut rows = []
  for target in (parse-targets $targets) {
    $rows = $rows | append (run-target $target)
  }

  cleanup-temp-packages
  release-lock

  let failures = $rows | where {|row| not $row.ok }
  if $json {
    print ($rows | to json --raw)
  } else {
    print ($rows | table -t light)
  }
  if ($failures | length) > 0 {
    print --stderr "fbr size verification failed: leaf artifact contains forbidden opposite-side markers."
    exit 1
  }
}
