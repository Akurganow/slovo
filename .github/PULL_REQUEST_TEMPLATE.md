Title this pull request as a Conventional Commit — `feat:`, `fix:`, `perf:`
— when it carries release-worthy changes. This repository squash-merges
pull requests, so the title becomes the release commit's header. The
release pipeline classifies that header. Any other title merges green but
releases nothing.

## Summary

-

## Test Plan

- [ ] The Swift check — `Scripts/diagnose.sh` on a macOS runner — is green on this pull request.

## Privacy / Security

- [ ] No secrets, local databases, seed files, signing keys, or credential files are included.
- [ ] Any change to audio, transcript egress, Keychain, permissions, or clipboard behavior is described above.
