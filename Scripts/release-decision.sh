#!/usr/bin/env bash
set -euo pipefail

# Release gate: decide whether the conventional commits since the last release
# anchor warrant a new release. This is the "skip when nothing to release" guard
# that release-it lacks natively — release-it computes the version number, but its
# conventional-changelog engine still recommends a patch for ANY non-empty commit
# set (docs/chore/ci included). This guard is the authority on whether a release
# is due at all, so a docs-only or chore-only push never cuts a release.
#
# A commit is release-worthy when it is a `feat`, `fix`, or `perf` (SemVer
# minor/patch), or a breaking change (`type!:` header or a `BREAKING CHANGE:`
# footer, SemVer major). Every other conventional type (docs, chore, ci, build,
# style, refactor, test, revert, merge commits, non-conventional subjects) does
# not, on its own, warrant a release. This trigger set matches the bump the pinned
# `conventionalcommits` preset would apply, so the guard and release-it agree.
#
# Output: prints `releasable=true|false` on stdout and, when running under GitHub
# Actions, appends the same key to $GITHUB_OUTPUT for downstream jobs.
#
# Input:
#   default                          classify commits in `<last v* tag>..HEAD` from
#                                    real git history.
#   RELEASE_DECISION_INPUT=stdin     classify NUL-separated commit messages read
#                                    from stdin. Used by the test suite to feed
#                                    deterministic fixtures with no git state.

emit() {
    printf 'releasable=%s\n' "$1"
    if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
        printf 'releasable=%s\n' "$1" >> "$GITHUB_OUTPUT"
    fi
}

# A single commit message (full body, first line is the conventional header).
# Returns 0 when the commit is release-worthy.
commit_is_releasable() {
    local message="$1"
    local header="${message%%$'\n'*}"

    # `type!:` or `type(scope)!:` — an explicit breaking change of any type.
    if [[ "$header" =~ ^[a-zA-Z]+(\([^\)]*\))?!: ]]; then
        return 0
    fi
    # feat / fix / perf headers (minor / patch / patch).
    if [[ "$header" =~ ^(feat|fix|perf)(\([^\)]*\))?: ]]; then
        return 0
    fi
    # A `BREAKING CHANGE:` / `BREAKING-CHANGE:` footer anywhere in the body.
    if grep -qE '^BREAKING[ -]CHANGE:' <<<"$message"; then
        return 0
    fi
    return 1
}

classify_stream() {
    # Reads NUL-separated commit messages; emits the aggregate decision. The whole
    # stream is drained (rather than short-circuiting) so an upstream `git log` in a
    # pipeline never receives SIGPIPE under `pipefail`.
    local message releasable=false
    while IFS= read -r -d '' message; do
        if commit_is_releasable "$message"; then
            releasable=true
        fi
    done
    emit "$releasable"
}

main() {
    if [[ "${RELEASE_DECISION_INPUT:-}" == "stdin" ]]; then
        classify_stream
        return
    fi

    local last_tag range
    if last_tag="$(git describe --tags --abbrev=0 --match 'v*' 2>/dev/null)"; then
        range="${last_tag}..HEAD"
    else
        # No prior release tag: the first release is always due.
        emit true
        return
    fi

    git log --format=%B -z "$range" | classify_stream
}

main "$@"
