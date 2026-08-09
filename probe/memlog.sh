#!/bin/bash
# Sample resident size of a running process at a fixed interval.
# Usage: memlog.sh <pid> <samples> <interval-seconds> <output-tsv>
# Records epoch, RSS in KB (ps resident size), VSZ in KB, and cumulative CPU time,
# so a run can be read for level and for trend without inferring either.
set -u
pid="$1"; samples="$2"; interval="$3"; out="$4"
printf 'epoch\trss_kb\tvsz_kb\tcputime\n' > "$out"
for _ in $(seq 1 "$samples"); do
  line=$(ps -o rss=,vsz=,time= -p "$pid" 2>/dev/null)
  [ -z "$line" ] && break
  printf '%s\t%s\n' "$(date +%s)" "$(echo "$line" | awk '{print $1"\t"$2"\t"$3}')" >> "$out"
  sleep "$interval"
done
