#!/usr/bin/env bash
# Decide latest from every published stable release, never API ordering.
set -euo pipefail

fail() { printf 'release-latest: %s\n' "$*" >&2; exit 1; }
[[ $# -eq 1 ]] || fail 'usage: release-latest.sh vMAJOR.MINOR.PATCH'
number='(0|[1-9][0-9]*)'
[[ $1 =~ ^v${number}\.${number}\.${number}$ ]] || fail 'invalid stable release tag'
[[ -n ${GH_REPO:-} ]] || fail 'GH_REPO is required'

# Capture before comparing: a failed later page must not produce a decision.
releases=$(gh api --paginate "repos/$GH_REPO/releases?per_page=100" \
    --jq '.[] | [.tag_name, .draft, .prerelease] | @tsv') || fail 'could not list all releases'

printf '%s\n' "$releases" | awk -F '\t' -v candidate="$1" '
    function valid_stable(tag) {
        return tag ~ /^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$/
    }
    function valid_preview(tag, parts, count, i, core) {
        core = tag
        sub(/-.*/, "", core)
        if (!valid_stable(core) || tag == core) return 0
        sub(/^[^-]*-/, "", tag)
        count = split(tag, parts, ".")
        for (i = 1; i <= count; i++) {
            if (parts[i] !~ /^[0-9A-Za-z-]+$/) return 0
            if (parts[i] ~ /^[0-9]+$/ && parts[i] ~ /^0[0-9]/) return 0
        }
        return 1
    }
    function newer(tag, parts, i) {
        split(substr(tag, 2), parts, ".")
        for (i = 1; i <= 3; i++) {
            if (length(parts[i]) != length(target[i])) return length(parts[i]) > length(target[i])
            # Prefixes force lexical comparison even for arbitrarily large numerals.
            if ("x" parts[i] != "x" target[i]) return ("x" parts[i]) > ("x" target[i])
        }
        return 0
    }
    BEGIN { split(substr(candidate, 2), target, "."); latest = "true" }
    /^$/ { next }
    {
        if (NF != 3 || ($2 != "true" && $2 != "false") || ($3 != "true" && $3 != "false")) {
            invalid = 1
            next
        }
        if ($2 == "true" || $3 == "true") next
        if (valid_preview($1)) next
        if (!valid_stable($1)) { invalid = 1; next }
        if (newer($1)) latest = "false"
    }
    END {
        if (invalid) {
            print "release-latest: malformed published release data" > "/dev/stderr"
            exit 1
        }
        print latest
    }
'
