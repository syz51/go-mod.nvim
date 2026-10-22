#!/usr/bin/env bash
# Extract one version's Markdown notes without changing the repository.
set -euo pipefail

fail() { printf 'release-notes: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 2 ]] || fail 'usage: release-notes.sh vMAJOR.MINOR.PATCH[-PRERELEASE] CHANGELOG'
tag=$1
changelog=$2
number='(0|[1-9][0-9]*)'
identifier='[0-9A-Za-z-]+'
[[ $tag =~ ^v${number}\.${number}\.${number}(-${identifier}(\.${identifier})*)?$ ]] || fail 'invalid release tag'
if [[ $tag == *-* ]]; then
    prerelease=${tag#*-}
    IFS=. read -r -a identifiers <<< "$prerelease"
    for part in "${identifiers[@]}"; do
        [[ ! $part =~ ^[0-9]+$ || $part == 0 || $part != 0* ]] || fail 'numeric prerelease identifiers cannot have leading zeros'
    done
fi
[[ -f $changelog ]] || fail 'changelog file does not exist'

awk -v version="${tag#v}" '
    function valid_date(date, parts, year, month, day, days) {
        if (date !~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) return 0
        split(date, parts, "-")
        year = parts[1] + 0
        month = parts[2] + 0
        day = parts[3] + 0
        if (year < 1 || month < 1 || month > 12 || day < 1) return 0
        days = 31
        if (month == 4 || month == 6 || month == 9 || month == 11) days = 30
        if (month == 2) days = 28 + (year % 4 == 0 && (year % 100 != 0 || year % 400 == 0))
        return day <= days
    }
    /^## / {
        heading = substr($0, 4)
        sub(/\r$/, "", heading)
        if (heading == "Unreleased") unreleased++
        # Count matching versions before validating dates so malformed duplicates fail too.
        matches = (heading == version || index(heading, version " ") == 1 || index(heading, version "\t") == 1)
        if (matches) found++
        active = matches && index(heading, version " - ") == 1 && valid_date(substr(heading, length(version) + 4))
        if (matches && !active) invalid = 1
        next
    }
    active { lines[++count] = $0; if ($0 ~ /[^[:space:]]/) nonempty = 1 }
    END {
        if (unreleased != 1 || found != 1 || invalid || !nonempty) {
            print "release-notes: expected one Unreleased heading and one nonempty VERSION - YYYY-MM-DD section with a valid date" > "/dev/stderr"
            exit 1
        }
        first = 1
        while (first <= count && lines[first] ~ /^[[:space:]]*$/) first++
        while (count >= first && lines[count] ~ /^[[:space:]]*$/) count--
        for (i = first; i <= count; i++) print lines[i]
    }
' "$changelog"
