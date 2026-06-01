#!/usr/bin/env nu

const default_output = "COVERAGE_ANALYSIS.md"

def coverage-rate [covered: int, total: int]: nothing -> float {
  if $total == 0 {
    0.0
  } else {
    ($covered * 100.0) / $total
  }
}

def fmt-percent [value: float]: nothing -> string {
  $"($value | math round --precision 2)%"
}

def parse-summary []: string -> table<file: string, package: string, covered: int, total: int, uncovered: int, coverage: float> {
  $in
  | lines
  | where $it =~ '^src/.*: \d+/\d+$'
  | each {|line|
    let parsed = $line | parse "{file}: {covered}/{total}" | first
    let short_file = $parsed.file | str replace "src/" ""
    let covered = $parsed.covered | into int
    let total = $parsed.total | into int
    let package = if ($short_file | str contains "/") {
      $short_file | split row "/" | first
    } else {
      "root"
    }
    {
      file: $short_file,
      package: $package,
      covered: $covered,
      total: $total,
      uncovered: ($total - $covered),
      coverage: (coverage-rate $covered $total),
    }
  }
  | where {|row| not ($row.file =~ '^brotli_.*_main/') }
  | where {|row| not ($row.file =~ '^fbr_size_.*_main/') }
  | sort-by -r uncovered
}

def package-stats []: table<file: string, package: string, covered: int, total: int, uncovered: int, coverage: float> -> table<package: string, covered: int, total: int, uncovered: int, coverage: float> {
  $in
  | group-by package --to-table
  | each {|group|
    let covered = $group.items | get covered | math sum
    let total = $group.items | get total | math sum
    {
      package: $group.package,
      covered: $covered,
      total: $total,
      uncovered: ($total - $covered),
      coverage: (coverage-rate $covered $total),
    }
  }
  | sort-by coverage
}

def render-markdown [
  generated_at: string
  file_stats: table<file: string, package: string, covered: int, total: int, uncovered: int, coverage: float>
  package_stats: table<package: string, covered: int, total: int, uncovered: int, coverage: float>
]: nothing -> string {
  let total_covered = $file_stats | get covered | math sum
  let total_lines = $file_stats | get total | math sum
  let total_uncovered = $total_lines - $total_covered
  let total_coverage = coverage-rate $total_covered $total_lines
  let uncovered_files = $file_stats | where uncovered > 0 | length
  let top_uncovered = $file_stats | first 5
  let lowest_coverage = $file_stats | sort-by coverage | first 5
  let file_rows = (
    $file_stats
    | each {|row|
      $"| `($row.file)` | `($row.package)` | ($row.covered) | ($row.total) | ($row.uncovered) | (fmt-percent $row.coverage) |"
    }
  )
  let package_rows = (
    $package_stats
    | each {|row|
      $"| `($row.package)` | ($row.covered) | ($row.total) | ($row.uncovered) | (fmt-percent $row.coverage) |"
    }
  )
  let top_rows = (
    $top_uncovered
    | each {|row|
      $"- `($row.file)`: ($row.uncovered) uncovered lines, (fmt-percent $row.coverage) covered"
    }
  )
  let lowest_rows = (
    $lowest_coverage
    | each {|row|
      $"- `($row.file)`: (fmt-percent $row.coverage) covered (($row.covered)/($row.total))"
    }
  )

  [
    "# fbr Coverage Analysis"
    ""
    $"Generated: `($generated_at)`"
    ""
    "Coverage source: `moon coverage analyze -- -f summary`"
    ""
    "Generated temporary main packages such as `src/brotli_*_main/` are excluded from the totals."
    ""
    "## Summary"
    ""
    "| Metric | Value |"
    "| --- | ---: |"
    $"| Coverage | (fmt-percent $total_coverage) |"
    $"| Covered lines | ($total_covered) |"
    $"| Total instrumented lines | ($total_lines) |"
    $"| Uncovered lines | ($total_uncovered) |"
    $"| Files in report | ($file_stats | length) |"
    $"| Files with uncovered lines | ($uncovered_files) |"
    $"| Packages in report | ($package_stats | length) |"
    ""
    "## Packages"
    ""
    "| Package | Covered | Total | Uncovered | Coverage |"
    "| --- | ---: | ---: | ---: | ---: |"
  ]
  | append $package_rows
  | append [
    ""
    "## Files"
    ""
    "| File | Package | Covered | Total | Uncovered | Coverage |"
    "| --- | --- | ---: | ---: | ---: | ---: |"
  ]
  | append $file_rows
  | append [
    ""
    "## Key Findings"
    ""
    "Files with the most uncovered lines:"
  ]
  | append $top_rows
  | append [
    ""
    "Lowest file coverage:"
  ]
  | append $lowest_rows
  | str join (char newline)
  | $in + (char newline)
}

def main [
  --output (-o): string = $default_output # Path for the Markdown report.
] {
  let coverage_run = ^moon coverage analyze -- -f summary | complete
  if $coverage_run.exit_code != 0 {
    print --stderr $coverage_run.stdout
    print --stderr $coverage_run.stderr
    exit $coverage_run.exit_code
  }

  let file_stats = $coverage_run.stdout | parse-summary
  let package_stats = $file_stats | package-stats
  let covered_count = $file_stats | get covered | math sum
  let total_count = $file_stats | get total | math sum
  let uncovered_count = $total_count - $covered_count
  let file_count = $file_stats | length
  let total_coverage = coverage-rate $covered_count $total_count
  let top_uncovered = $file_stats | first 5

  print "\n╔════════════════════════════════════════════════════════════════╗"
  print "║              测试覆盖率分析报告 - fbr 库                      ║"
  print "╚════════════════════════════════════════════════════════════════╝\n"

  print "📊 总体统计"
  print "─────────────────────────────────────────────────────────────────"
  print $"  覆盖率: (fmt-percent $total_coverage)"
  print $"  已覆盖行数: ($covered_count)"
  print $"  总计可统计行数: ($total_count)"
  print $"  未覆盖行数: ($uncovered_count)"
  print $"  涉及文件数: ($file_count)\n"

  print "📁 各文件未覆盖行数统计"
  print "─────────────────────────────────────────────────────────────────"
  $file_stats | each {|row|
    print $"  ($row.file): ($row.uncovered) 行，覆盖率 (fmt-percent $row.coverage)"
  }

  print "\n💡 关键发现"
  print "─────────────────────────────────────────────────────────────────"
  print "  未覆盖代码最多的文件:"
  $top_uncovered | each {|row|
    print $"    • ($row.file): ($row.uncovered) 行，覆盖率 (fmt-percent $row.coverage)"
  }

  let output_dir = $output | path dirname
  if $output_dir != "." {
    mkdir $output_dir
  }
  render-markdown (date now | into string) $file_stats $package_stats | save --force $output

  print $"\n📝 详细覆盖率报告已保存: ($output)"
}
