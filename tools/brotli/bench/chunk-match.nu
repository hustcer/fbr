#!/usr/bin/env nu

def parse-min-lengths [text: string]: nothing -> list<int> {
  $text
  | split row ","
  | each {|value| $value | str trim | into int }
}

def main [
  input: string
  --chunk-size: int = 65535
  --max-chunks: int = 16
  --min-lengths: string = "4,8,16,24,32"
  --json
]: nothing -> nothing {
  if not ($input | path exists) {
    print --stderr $"Missing diagnostic input: ($input)"
    exit 1
  }
  if $chunk_size <= 0 {
    print --stderr "chunk-size must be positive"
    exit 1
  }
  if $max_chunks <= 0 {
    print --stderr "max-chunks must be positive"
    exit 1
  }

  let input_abs = ($input | path expand)
  let min_lengths = (parse-min-lengths $min_lengths | str join ",")
  let analyzer = r#'
const fs = require("fs");

const [input, chunkSizeText, maxChunksText, minLengthsText] = process.argv.slice(1);
const data = fs.readFileSync(input);
const chunkSize = Number(chunkSizeText);
const maxChunks = Number(maxChunksText);
const minLengths = minLengthsText.split(",").filter(Boolean).map(Number);
const maxMatchLength = 4096;
const maxMatchChecks = 4;

function hashAt(position) {
  if (position + 2 >= data.length) return 0;
  return ((data[position] * 257) ^ (data[position + 1] * 17) ^ data[position + 2]) & 4095;
}

function uniqueCount(start, end) {
  const seen = new Uint8Array(256);
  let count = 0;
  for (let position = start; position < end; position += 1) {
    const value = data[position];
    if (seen[value] === 0) {
      seen[value] = 1;
      count += 1;
    }
  }
  return count;
}

function sampledFourByteDensity(start, end) {
  if (end - start < 4) return 0;
  const table = new Int32Array(4096);
  table.fill(-1);
  const step = 256;
  let samples = 0;
  let matches = 0;
  for (let position = start; position < end - 3; position += step) {
    const hash = hashAt(position);
    const candidate = table[hash];
    table[hash] = position;
    samples += 1;
    if (
      candidate >= 0 &&
      data[position] === data[candidate] &&
      data[position + 1] === data[candidate + 1] &&
      data[position + 2] === data[candidate + 2] &&
      data[position + 3] === data[candidate + 3]
    ) {
      matches += 1;
    }
  }
  return samples === 0 ? 0 : matches / samples;
}

function buildPrevious(start, end) {
  const previous = new Int32Array(end - start);
  previous.fill(-1);
  const table = new Int32Array(4096);
  table.fill(-1);
  for (let position = start; position < end - 2; position += 1) {
    const hash = hashAt(position);
    const localPosition = position - start;
    previous[localPosition] = table[hash];
    table[hash] = localPosition;
  }
  return previous;
}

function longestPreviousMatch(start, end, previous, position) {
  if (position + 3 >= end) return 0;
  let bestLength = 0;
  let candidate = previous[position - start];
  let checked = 0;
  while (candidate >= 0 && checked < maxMatchChecks) {
    const candidatePosition = start + candidate;
    if (
      data[position] === data[candidatePosition] &&
      data[position + 1] === data[candidatePosition + 1] &&
      data[position + 2] === data[candidatePosition + 2] &&
      data[position + 3] === data[candidatePosition + 3]
    ) {
      let length = 4;
      while (
        length < maxMatchLength &&
        position + length < end &&
        data[position + length] === data[candidatePosition + length]
      ) {
        length += 1;
      }
      if (length > bestLength) bestLength = length;
    }
    candidate = previous[candidate];
    checked += 1;
  }
  return bestLength;
}

function analyzeMinLength(start, end, previous, minLength) {
  let position = start;
  let literalStart = start;
  let commands = 0;
  let copyBytes = 0;
  let literalBytes = 0;
  let capped = false;
  while (position < end) {
    const matchLength = longestPreviousMatch(start, end, previous, position);
    if (matchLength >= minLength) {
      literalBytes += position - literalStart;
      copyBytes += matchLength;
      commands += 1;
      if (commands > 1200) {
        capped = true;
        break;
      }
      position += matchLength;
      literalStart = position;
    } else {
      position += 1;
    }
  }
  if (!capped && literalStart < end) {
    literalBytes += end - literalStart;
    commands += 1;
  }
  const length = end - start;
  return {
    min_length: minLength,
    commands,
    literal_bytes: literalBytes,
    copy_bytes: copyBytes,
    copy_ratio: length === 0 ? 0 : copyBytes / length,
    capped,
  };
}

const chunkCount = Math.min(maxChunks, Math.ceil(data.length / chunkSize));
const rows = [];
for (let chunk = 0; chunk < chunkCount; chunk += 1) {
  const start = chunk * chunkSize;
  const end = Math.min(data.length, start + chunkSize);
  const previous = buildPrevious(start, end);
  const chunkInfo = {
    chunk,
    start,
    length: end - start,
    unique_literals: uniqueCount(start, end),
    sampled_4byte_density: sampledFourByteDensity(start, end),
  };
  for (const minLength of minLengths) {
    rows.push({...chunkInfo, ...analyzeMinLength(start, end, previous, minLength)});
  }
}

console.log(JSON.stringify(rows));
'#

  let run = (
    node -e $analyzer -- $input_abs ($chunk_size | into string) ($max_chunks | into string) $min_lengths
    | complete
  )
  if $run.exit_code != 0 {
    print --stderr $run.stderr
    exit $run.exit_code
  }

  if $json {
    print $run.stdout
  } else {
    print ($run.stdout | from json | table)
  }
}
