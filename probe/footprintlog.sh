#!/bin/bash
# Sample phys_footprint of a running process at a fixed interval.
#
# ps RSS and phys_footprint answer different questions. RSS counts every resident
# page including clean, shared, file-backed mappings the kernel can evict for free;
# phys_footprint counts the dirty and compressed pages the process is actually
# charged for. For an app that maps the system icon cache the two differ by
# gigabytes, so record both rather than choosing one.
#
# Usage: footprintlog.sh <pid> <samples> <interval-seconds> <output-tsv>
set -u
pid="$1"; samples="$2"; interval="$3"; out="$4"
printf 'epoch\tfootprint_mb\trss_kb\n' > "$out"
for _ in $(seq 1 "$samples"); do
  fp=$(footprint -p "$pid" 2>/dev/null | awk -F'phys_footprint:' '/^ *phys_footprint:/ {gsub(/[^0-9]/,"",$2); print $2; exit}')
  rss=$(ps -o rss= -p "$pid" 2>/dev/null | tr -d ' ')
  [ -z "$rss" ] && break
  printf '%s\t%s\t%s\n' "$(date +%s)" "${fp:-NA}" "$rss" >> "$out"
  sleep "$interval"
done
