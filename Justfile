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

# Bench: Run performance benchmarks
bench:
    moon bench -p benchmarks

# Run tests
test:
    moon test --target all

# Run the full Brotli practical release validation gate
brotli-release:
    nu tools/brotli/release/validate.nu

# Run a quick Brotli release validation smoke gate
brotli-release-smoke:
    nu tools/brotli/release/validate.nu --skip-moon --skip-conformance --skip-ratio --skip-package --decoder-fuzz-limit 2 --roundtrip-count 1 --roundtrip-max-len 16 --roundtrip-qualities 2

# Run Brotli release validation with a generated deterministic decoder fuzz corpus
brotli-release-generated-fuzz count='1000' seed='1':
    nu tools/brotli/release/validate.nu --skip-moon --skip-conformance --skip-ratio --skip-package --generated-fuzz-count {{ count }} --generated-fuzz-seed {{ seed }}

# Run Brotli packaging and publish dry-run validation only
brotli-release-package:
    nu tools/brotli/release/validate.nu --skip-moon --skip-conformance --skip-ratio --skip-fuzz

# Run the Brotli long fuzz soak gate
brotli-fuzz-soak duration_minutes='1440':
    nu tools/brotli/fuzz/soak.nu --duration-min {{ duration_minutes }}

# Run bounded full-corpus Brotli fuzz soak iterations
brotli-fuzz-soak-bounded iterations='3':
    nu tools/brotli/fuzz/soak.nu --duration-min 1440 --max-iterations {{ iterations }}

# Run one short Brotli fuzz soak iteration
brotli-fuzz-soak-smoke:
    nu tools/brotli/fuzz/soak.nu --duration-min 0 --max-iterations 1 --decoder-limit 2 --roundtrip-count 1 --roundtrip-max-len 16 --roundtrip-qualities 2

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
