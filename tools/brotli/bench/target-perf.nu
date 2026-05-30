#!/usr/bin/env nu

const bench_dir = "target/brotli-bench"
const harness_lock_dir = "tools/brotli/.harness-lock"
const temp_test = "src/brotli_target_perf_wbtest.mbt"
const temp_main_dir = "src/brotli_target_perf_main"
const temp_main_pkg = "src/brotli_target_perf_main/moon.pkg"
const temp_main = "src/brotli_target_perf_main/main.mbt"
const native_cc_o0 = "tools/brotli/bench/native-cc-o0.nu"

def process-alive [pid: int]: nothing -> bool {
  let probe = (^ps -p ($pid | into string) | complete)
  $probe.exit_code == 0
}

def lock-pid-path []: nothing -> string {
  $harness_lock_dir | path join "pid"
}

def stale-harness-lock []: nothing -> bool {
  let pid_path = (lock-pid-path)
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

def acquire-harness-lock []: nothing -> nothing {
  let made = (^mkdir $harness_lock_dir | complete)
  if $made.exit_code != 0 {
    if (stale-harness-lock) {
      rm --force --recursive $harness_lock_dir
      let retry = (^mkdir $harness_lock_dir | complete)
      if $retry.exit_code == 0 {
        write-lock-pid
      } else {
        print --stderr "Another Brotli harness is running; retry after it finishes."
        exit 1
      }
    } else {
      let pid_path = (lock-pid-path)
      let owner = if ($pid_path | path exists) { open --raw $pid_path | str trim } else { "unknown" }
      print --stderr $"Another Brotli harness is running \(pid: ($owner)\); retry after it finishes."
      exit 1
    }
  } else {
    write-lock-pid
  }
}

def release-harness-lock []: nothing -> nothing {
  rm --force --recursive $harness_lock_dir
}

def parse-csv-ints [text: string]: nothing -> list<int> {
  $text | split row "," | each {|value| $value | str trim | into int }
}

def parse-csv-strings [text: string]: nothing -> list<string> {
  $text | split row "," | each {|value| $value | str trim }
}

def write-placeholder-temp-test [path: string]: nothing -> nothing {
  [
    "// Placeholder for tools/brotli/bench/target-perf.nu."
    "// The harness rewrites this ignored file during a target-perf run."
    ""
  ] | str join (char newline) | save --force $path
}

def write-placeholder-main-package []: nothing -> nothing {
  mkdir $temp_main_dir
  [
    "options("
    "  \"is-main\": true,"
    ")"
    ""
  ] | str join (char newline) | save --force $temp_main_pkg
  [
    "fn main {"
    "  ()"
    "}"
    ""
  ] | str join (char newline) | save --force $temp_main
}

def parse-size-marker [text: string]: nothing -> int {
  $text
  | lines
  | where {|line| $line | str starts-with "MBT_PERF_SIZE=" }
  | first
  | str replace "MBT_PERF_SIZE=" ""
  | into int
}

def native-cc-label [target: string, release: bool]: nothing -> string {
  if $target == "native" and $release {
    "cc-o0"
  } else {
    "default"
  }
}

def run-moon-main [
  target: string
  release_flag: list<string>
  release: bool
]: nothing -> record {
  if $target == "native" and $release {
    let cc = ($native_cc_o0 | path expand)
    with-env { MOON_CC: $cc } {
      ^moon run --target $target ...$release_flag $temp_main_dir | complete
    }
  } else {
    ^moon run --target $target ...$release_flag $temp_main_dir | complete
  }
}

def make-temp-main [
  mode: string
  input: string
  quality: int
  repeats: int
  expected_total: int
  max_output_size: int
  native_file_input: bool
]: nothing -> nothing {
  mkdir $temp_main_dir
  let input_abs = ($input | path expand)
  let node_code = '
const fs = require("fs");
const [inputPath, mode, qualityText, repeatsText, expectedTotalText, maxOutputText, pkgPath, mainPath, nativeFileInputText] = process.argv.slice(1);
const data = fs.readFileSync(inputPath);
const quality = Number(qualityText);
const repeats = Number(repeatsText);
const expectedTotal = Number(expectedTotalText);
const maxOutput = Number(maxOutputText);
const nativeFileInput = nativeFileInputText === "true";
const rows = [];
for (let i = 0; i < data.length; i += 16) {
  rows.push("  " + Array.from(data.slice(i, i + 16), b =>
    "0x" + b.toString(16).toUpperCase().padStart(2, "0")
  ).join(", "));
}
const literal = rows.join(",\n");
const byteList = bytes => Array.from(bytes, b => `(${b}).to_byte()`).join(", ");
const pathLiteral = byteList(Buffer.from(inputPath + "\0", "utf8"));
const modeLiteral = byteList(Buffer.from("rb\0", "utf8"));
const inputDecl = nativeFileInput
  ? "  let input = brotli_target_perf_read_file()"
  : `  let input : FixedArray[Byte] = [
${literal}
  ]`;
const nativePrelude = nativeFileInput ? `///|
#external
type BrotliTargetPerfFile

///|
#borrow(path, mode)
extern "c" fn brotli_target_perf_fopen(path : Bytes, mode : Bytes) -> BrotliTargetPerfFile = "moonbit_fopen_ffi"

///|
#borrow(file)
extern "c" fn brotli_target_perf_is_null(file : BrotliTargetPerfFile) -> Bool = "moonbit_is_null"

///|
#borrow(file)
extern "c" fn brotli_target_perf_fseek(file : BrotliTargetPerfFile, offset : Int, whence : Int) -> Int = "moonbit_fseek_ffi"

///|
#borrow(file)
extern "c" fn brotli_target_perf_ftell(file : BrotliTargetPerfFile) -> Int = "moonbit_ftell_ffi"

///|
#borrow(buf, file)
extern "c" fn brotli_target_perf_fread(buf : Bytes, size : Int, nitems : Int, file : BrotliTargetPerfFile) -> Int = "moonbit_fread_ffi"

///|
extern "c" fn brotli_target_perf_fclose(file : BrotliTargetPerfFile) -> Int = "moonbit_fclose_ffi"

///|
fn brotli_target_perf_read_file() -> FixedArray[Byte] {
  let path = Bytes::from_array([${pathLiteral}])
  let mode = Bytes::from_array([${modeLiteral}])
  let file = brotli_target_perf_fopen(path, mode)
  if brotli_target_perf_is_null(file) {
    return FixedArray::make(0, (0).to_byte())
  }
  if brotli_target_perf_fseek(file, 0, 2) != 0 {
    ignore(brotli_target_perf_fclose(file))
    return FixedArray::make(0, (0).to_byte())
  }
  let size = brotli_target_perf_ftell(file)
  if size < 0 {
    ignore(brotli_target_perf_fclose(file))
    return FixedArray::make(0, (0).to_byte())
  }
  if brotli_target_perf_fseek(file, 0, 0) != 0 {
    ignore(brotli_target_perf_fclose(file))
    return FixedArray::make(0, (0).to_byte())
  }
  let input : FixedArray[Byte] = FixedArray::make(size, (0).to_byte())
  let bytes = input.unsafe_reinterpret_as_bytes()
  let read = brotli_target_perf_fread(bytes, 1, size, file)
  ignore(brotli_target_perf_fclose(file))
  if read != size {
    return FixedArray::make(0, (0).to_byte())
  }
  input
}

` : "";
let body;
if (mode === "decode") {
  body = `    let result = try? @fbr.unbrotli_sync(
      input,
      opts={ out: None, max_output_size: ${maxOutput}, max_input_size: input.length() + 1 },
    )
    match result {
      Ok(decoded) => total += decoded.length()
      Err(_) => {
        println("MBT_PERF_ERROR=decode")
        return
      }
    }`;
} else if (mode === "encode") {
  body = `    let result = try? @fbr.brotli_sync(
      input,
      opts={ quality: ${quality}, window_bits: 22, max_input_size: input.length() + 1 },
    )
    match result {
      Ok(encoded) => {
        if total == 0 {
          println("MBT_PERF_SIZE=" + encoded.length().to_string())
        }
        total += encoded.length()
      }
      Err(_) => {
        println("MBT_PERF_ERROR=encode")
        return
      }
    }`;
} else {
  throw new Error("unsupported mode: " + mode);
}
const check = mode === "decode"
  ? `  if total == ${expectedTotal} {
    println("MBT_PERF_OK=" + total.to_string())
  } else {
    println("MBT_PERF_ERROR=decoded-total-" + total.to_string())
  }`
  : `  if total > 0 {
    println("MBT_PERF_OK=" + total.to_string())
  } else {
    println("MBT_PERF_ERROR=encoded-total")
  }`;
const pkg = `import {
  "hustcer/fbr",
}

options(
  "is-main": true,
)
`;
const content = `${nativePrelude}///|
fn main {
${inputDecl}
  let mut total = 0
  for _ in 0..<${repeats} {
${body}
  }
${check}
}
`;
fs.writeFileSync(pkgPath, pkg);
fs.writeFileSync(mainPath, content);
'
  node -e $node_code $input_abs $mode ($quality | into string) ($repeats | into string) ($expected_total | into string) ($max_output_size | into string) $temp_main_pkg $temp_main ($native_file_input | into string)
}

def run-target [
  target: string
  repeats: int
  samples: int
  release: bool
]: nothing -> record {
  let release_flag = if $release { ["--release"] } else { [] }
  let warmup = run-moon-main $target $release_flag $release
  if $warmup.exit_code != 0 {
    print --stderr $warmup.stdout
    print --stderr $warmup.stderr
    exit $warmup.exit_code
  }
  if $warmup.stdout =~ "MBT_PERF_ERROR=" {
    print --stderr $warmup.stdout
    exit 1
  }
  let encoded_size = if $warmup.stdout =~ "MBT_PERF_SIZE=" {
    parse-size-marker $warmup.stdout
  } else {
    0
  }
  mut times = []
  for _ in 0..<$samples {
    let started = date now
    let run = run-moon-main $target $release_flag $release
    let elapsed = ((date now) - $started | into int) / 1_000_000
    if $run.exit_code != 0 {
      print --stderr $run.stdout
      print --stderr $run.stderr
      exit $run.exit_code
    }
    if $run.stdout =~ "MBT_PERF_ERROR=" {
      print --stderr $run.stdout
      exit 1
    }
    $times = ($times | append $elapsed)
  }
  {
    target: $target,
    native_cc: (native-cc-label $target $release),
    total_min_ms: ($times | math min),
    total_avg_ms: ($times | math avg),
    per_op_min_ms: (($times | math min) / $repeats),
    per_op_avg_ms: (($times | math avg) / $repeats),
    encoded_size: $encoded_size,
    samples_ms: $times,
  }
}

def google-decode [
  compressed: string
  repeats: int
  samples: int
]: nothing -> record {
  let compressed_abs = ($compressed | path expand)
  mut times = []
  for _ in 0..<$samples {
    let started = date now
    let run = (
      bash -lc 'for i in $(seq 1 "$1"); do brotli -d -c "$2" > /dev/null || exit 1; done' _ ($repeats | into string) $compressed_abs
      | complete
    )
    let elapsed = ((date now) - $started | into int) / 1_000_000
    if $run.exit_code != 0 {
      print --stderr $run.stderr
      exit $run.exit_code
    }
    $times = ($times | append $elapsed)
  }
  {
    target: "google",
    total_min_ms: ($times | math min),
    total_avg_ms: ($times | math avg),
    per_op_min_ms: (($times | math min) / $repeats),
    per_op_avg_ms: (($times | math avg) / $repeats),
    samples_ms: $times,
  }
}

def google-encode [
  input: string
  quality: int
  repeats: int
  samples: int
]: nothing -> record {
  mkdir $bench_dir
  let input_abs = ($input | path expand)
  let out = (
    $bench_dir
    | path join $"(($input | path basename)).google.q($quality).br"
    | path expand
  )
  let size_run = (bash -lc 'brotli -q "$1" -c "$2" > "$3"' _ ($quality | into string) $input_abs $out | complete)
  if $size_run.exit_code != 0 {
    print --stderr $size_run.stderr
    exit $size_run.exit_code
  }
  mut times = []
  for _ in 0..<$samples {
    let started = date now
    let run = (
      bash -lc 'for i in $(seq 1 "$1"); do brotli -q "$2" -c "$3" > /dev/null || exit 1; done' _ ($repeats | into string) ($quality | into string) $input_abs
      | complete
    )
    let elapsed = ((date now) - $started | into int) / 1_000_000
    if $run.exit_code != 0 {
      print --stderr $run.stderr
      exit $run.exit_code
    }
    $times = ($times | append $elapsed)
  }
  {
    target: "google",
    encoded_size: (ls $out | get size.0 | into int),
    total_min_ms: ($times | math min),
    total_avg_ms: ($times | math avg),
    per_op_min_ms: (($times | math min) / $repeats),
    per_op_avg_ms: (($times | math avg) / $repeats),
    samples_ms: $times,
  }
}

def main [
  input: string
  --mode (-m): string = "decode" # decode or encode
  --expected (-e): string = "" # Required for decode: uncompressed expected file
  --quality (-q): int = 11 # Used for encode
  --targets (-t): string = "wasm-gc,native"
  --repeats (-r): int = 10
  --samples (-s): int = 5
  --debug # Run MoonBit with debug profile instead of release
  --json
]: nothing -> nothing {
  if $mode != "decode" and $mode != "encode" {
    print --stderr $"Unsupported mode: ($mode)"
    exit 1
  }
  if not ($input | path exists) {
    print --stderr $"Missing benchmark input: ($input)"
    exit 1
  }
  if $mode == "decode" and (($expected | str trim) == "" or not ($expected | path exists)) {
    print --stderr "Decode mode requires --expected <uncompressed-file>"
    exit 1
  }

  let targets = parse-csv-strings $targets
  let release = not $debug
  let input_size = (ls $input | get size.0 | into int)
  mut rows = []
  acquire-harness-lock

  if $mode == "decode" {
    let decoded_size = (ls $expected | get size.0 | into int)
    let expected_total = $decoded_size * $repeats
    let google = google-decode $input $repeats $samples
    for target in $targets {
      make-temp-main decode $input 0 $repeats $expected_total $decoded_size ($target == "native")
      let measured = run-target $target $repeats $samples $release
      $rows = ($rows | append {
        mode: "decode",
        target: $target,
        native_cc: $measured.native_cc,
        input_bytes: $input_size,
        decoded_bytes: $decoded_size,
        target_min_ms: $measured.per_op_min_ms,
        target_avg_ms: $measured.per_op_avg_ms,
        google_min_ms: $google.per_op_min_ms,
        google_avg_ms: $google.per_op_avg_ms,
        slowdown_min: ($measured.per_op_min_ms / $google.per_op_min_ms),
        slowdown_avg: ($measured.per_op_avg_ms / $google.per_op_avg_ms),
      })
    }
  } else {
    let google = google-encode $input $quality $repeats $samples
    for target in $targets {
      make-temp-main encode $input $quality $repeats 0 0 ($target == "native")
      let measured = run-target $target $repeats $samples $release
      if $measured.encoded_size <= 0 {
        print --stderr $"Target ($target) did not report MBT_PERF_SIZE"
        exit 1
      }
      $rows = ($rows | append {
        mode: "encode",
        target: $target,
        native_cc: $measured.native_cc,
        quality: $quality,
        input_bytes: $input_size,
        moonbit_size: $measured.encoded_size,
        google_size: $google.encoded_size,
        size_overhead: (($measured.encoded_size - $google.encoded_size) / $google.encoded_size),
        target_min_ms: $measured.per_op_min_ms,
        target_avg_ms: $measured.per_op_avg_ms,
        google_min_ms: $google.per_op_min_ms,
        google_avg_ms: $google.per_op_avg_ms,
        slowdown_min: ($measured.per_op_min_ms / $google.per_op_min_ms),
        slowdown_avg: ($measured.per_op_avg_ms / $google.per_op_avg_ms),
      })
    }
  }

  write-placeholder-temp-test $temp_test
  write-placeholder-main-package
  release-harness-lock
  if $json {
    print ($rows | to json --raw)
  } else {
    print ($rows | table)
  }
}
