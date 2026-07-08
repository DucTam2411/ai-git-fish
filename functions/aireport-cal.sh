#!/bin/sh
# aireport-cal.sh YYYY-MM-DD — print the month calendar grid for that date.
# Standalone POSIX script so fzf's --preview never depends on fish autoload.
d="$1"
y=$(date -j -f "%Y-%m-%d" "$d" +%Y 2>/dev/null || date -d "$d" +%Y)
m=$(date -j -f "%Y-%m-%d" "$d" +%-m 2>/dev/null || date -d "$d" +%-m)
cal "$m" "$y"
