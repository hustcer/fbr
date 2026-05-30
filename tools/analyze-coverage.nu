#!/usr/bin/env nu

# 解析覆盖率报告
let coverage_output = moon coverage analyze o+e>| complete | get stdout

# 提取总体统计
let total_line = $coverage_output | lines | first
let total_uncovered = $total_line | parse "Total: {uncovered} uncovered line(s) in {files} file(s)" | first

print "\n╔════════════════════════════════════════════════════════════════╗"
print "║              测试覆盖率分析报告 - fbr 库                      ║"
print "╚════════════════════════════════════════════════════════════════╝\n"

print "📊 总体统计"
print "─────────────────────────────────────────────────────────────────"
print $"  未覆盖行数: ($total_uncovered.uncovered)"
print $"  涉及文件数: ($total_uncovered.files)\n"

# 解析每个文件的未覆盖行数
let file_stats = $coverage_output 
  | lines 
  | where $it =~ '^\d+ uncovered line\(s\) in src/'
  | each {|line|
      let parsed = $line | parse "{count} uncovered line(s) in {file}:" | first
      {
        file: ($parsed.file | str replace "src/" ""),
        uncovered: ($parsed.count | into int)
      }
    }
  | sort-by -r uncovered

print "📁 各文件未覆盖行数统计"
print "─────────────────────────────────────────────────────────────────"
$file_stats | each {|row|
  print $"  ($row.file): ($row.uncovered) 行"
}

# 计算覆盖率百分比（需要统计总行数）
print "\n💡 关键发现"
print "─────────────────────────────────────────────────────────────────"

# 找出未覆盖最多的文件
let top_uncovered = $file_stats | first 3
print "  未覆盖代码最多的文件:"
$top_uncovered | each {|row|
  print $"    • ($row.file): ($row.uncovered) 行"
}

print "\n📝 详细覆盖率报告已保存"
