set shell := ['nu', '-m', 'light', '-c']

# The export setting causes all just variables
# to be exported as environment variables.

set export

JUST_FILE_PATH := justfile()
NU_DIR := parent_directory(`$nu.current-exe`)
[private]
_inc_plugin := if os_family() == 'windows' { 'nu_plugin_inc.exe' } else { 'nu_plugin_inc' }

# Just commands aliases
# alias d := dev
# alias b := build

alias t := test

# Show all available commands by default
default:
    @just --list --list-prefix "··· "

# Update Moonbit dependencies
i: __setup
    moon update

# Format all Moonbit code
fmt: __setup
    moon info
    moon fmt

# Run comprehensive code check
lint:
    moon check --target all

# Build: Build the application in production mode
b: __setup
    moon build --target all

# Bench: Run Brotli performance benchmarks and regenerate the release report
bench:
    nu tools/bench/report.nu

# Run tests
test:
    moon test --target all

# Run the full Brotli practical release validation gate
release:
    nu tools/release/validate.nu

# Run a quick Brotli release validation smoke gate
release-smoke:
    nu tools/release/validate.nu --skip-moon --skip-conformance --skip-ratio --skip-package --decoder-fuzz-limit 2 --roundtrip-count 1 --roundtrip-max-len 16 --roundtrip-qualities 2

# Run Brotli release validation with a generated deterministic decoder fuzz corpus
release-generated-fuzz count='1000' seed='1':
    nu tools/release/validate.nu --skip-moon --skip-conformance --skip-ratio --skip-size --skip-package --generated-fuzz-count {{ count }} --generated-fuzz-seed {{ seed }}

# Run the upstream Brotli conformance corpus
conformance:
    nu tools/conformance/run.nu

# Run one upstream Brotli conformance fixture by expected-file name
conformance-fixture fixture:
    nu tools/conformance/run.nu --fixture {{ fixture }}

# Run the checked-in Brotli decoder fuzz corpus
fuzz target='native' limit='0' batch_size='25':
    nu tools/fuzz/run.nu --target {{ target }} --limit {{ limit }} --batch-size {{ batch_size }}

# Run deterministic Brotli encoder roundtrip fuzz
roundtrip target='native' count='12' max_len='2048' qualities='0,1,2,9,11' batch_size='25':
    nu tools/fuzz/roundtrip.nu --target {{ target }} --count {{ count }} --max-len {{ max_len }} --qualities {{ qualities }} --batch-size {{ batch_size }}

# Run the Brotli ratio and external-decode harness
ratio input='target/bench/silesia-2m.bin' qualities='2,3,4,5,6,7,8,9':
    nu tools/bench/ratio.nu {{ input }} --qualities {{ qualities }} --json

# Run wasm-gc/native Brotli decode target-perf
target-perf-decode input expected targets='wasm-gc,native' repeats='10' samples='5':
    nu tools/bench/target-perf.nu {{ input }} --mode decode --expected {{ expected }} --targets {{ targets }} --repeats {{ repeats }} --samples {{ samples }} --json

# Run wasm-gc/native Brotli encode target-perf
target-perf-encode input quality='11' targets='wasm-gc,native' repeats='10' samples='5':
    nu tools/bench/target-perf.nu {{ input }} --mode encode --quality {{ quality }} --targets {{ targets }} --repeats {{ repeats }} --samples {{ samples }} --json

# Same-time decode comparison of the working tree vs a baseline git ref
decode-compare base='HEAD' qualities='0,5,9,11' targets='wasm-gc,native' rounds='2':
    nu tools/bench/decode-compare.nu --base {{ base }} --qualities {{ qualities }} --targets {{ targets }} --rounds {{ rounds }}

# Same-time encode speed and size comparison of the working tree vs a baseline git ref
encode-compare base='HEAD' inputs='target/brotli-bench/silesia-64k.bin,target/brotli-bench/silesia-128k.bin' qualities='0,1,2,3,4,5,6,7,8,9,10,11' targets='wasm-gc,native' repeats='3' samples='3' rounds='2':
    nu tools/bench/encode-compare.nu --base {{ base }} --inputs {{ inputs }} --qualities {{ qualities }} --targets {{ targets }} --repeats {{ repeats }} --samples {{ samples }} --rounds {{ rounds }}

# Verify decode-only and encode-only release artifacts do not pull the opposite side
size targets='js':
    nu tools/size/verify.nu --targets {{ targets }}

# Run Brotli packaging and publish dry-run validation only
release-package:
    nu tools/release/validate.nu --skip-moon --skip-conformance --skip-ratio --skip-fuzz --skip-size

# Run the accepted Brotli release-candidate gate set
release-candidate generated_count='1000' seed='1' soak_iterations='3':
    just release
    just release-generated-fuzz {{ generated_count }} {{ seed }}
    just fuzz-soak-bounded {{ soak_iterations }}

# Run a quick smoke version of the Brotli release-candidate gate set
release-candidate-smoke:
    just release-smoke
    just release-generated-fuzz 12 12345
    just fuzz-soak-smoke

# Run the Brotli long fuzz soak gate
fuzz-soak duration_minutes='1440':
    nu tools/fuzz/soak.nu --duration-min {{ duration_minutes }}

# Run bounded full-corpus Brotli fuzz soak iterations
fuzz-soak-bounded iterations='3':
    nu tools/fuzz/soak.nu --duration-min 1440 --max-iterations {{ iterations }}

# Run one short Brotli fuzz soak iteration
fuzz-soak-smoke:
    nu tools/fuzz/soak.nu --duration-min 0 --max-iterations 1 --decoder-limit 2 --roundtrip-count 1 --roundtrip-max-len 16 --roundtrip-qualities 2

# Clean build directories
clean:
    #!/usr/bin/env nu

    moon clean
    print $'(ansi pb)Directories have been cleaned !(ansi reset)'

# Scan code for spelling errors, requires `typos-cli` installed locally. Usage: `just typos` or `just typos raw`
typos output=('table'):
    #!/usr/bin/env nu

    $env.config.table.mode = 'light'
    $env.config.color_config.leading_trailing_space_bg = { attr: n }
    let output = '{{ output }}'
    if not ((which typos | length) > 0) {
      print $'(ansi y)[WARN]: (ansi reset)`Typos` not installed, please install it by running `brew install typos-cli`...'
      exit 2
    }
    if $output != 'table' { typos .; exit 0 }
    typos . --format brief
      | lines
      | split column :
      | rename file line column correction
      | sort-by correction
      | update line {|l| $'(ansi pb)($l.line)(ansi reset)' }
      | update column {|l| $'(ansi pb)($l.column)(ansi reset)' }
      | upsert author {|l|
          let line = ($l.line | ansi strip)
          git blame $l.file -L $'($line),($line)' --porcelain | lines | get 1 | str replace 'author ' ''
        }
      | move author --before correction

# Check outdated dependencies: `just outdated` checks Node dependencies, `just outdated mbt` checks MoonBit dependencies
outdated:
    #!/usr/bin/env nu

    cd ($env.JUST_FILE_PATH | path dirname)
    moon update
    let diff = (git diff moon.mod.json)
    if ($diff | is-empty) {
      print $'(ansi g)All MoonBit dependencies are up to date!(ansi reset)'
    } else {
      print $'(ansi y)MoonBit dependency updates available:(ansi reset)'
      print $diff
    }

__setup:
    #!/usr/bin/env nu
    let version = moon version | lines | first
    print $'Current moon Version: (ansi g)($version)(ansi reset)'
    print $'(ansi p)------------------------------------->(ansi reset)(char nl)'

# Plugins only need to be registered once
_register_plugins:
    #!/usr/bin/env nu
    let incExists = not (scope commands | where name == 'inc' | is-empty)
    if not $incExists { plugin add {{ join(NU_DIR, _inc_plugin) }} }
