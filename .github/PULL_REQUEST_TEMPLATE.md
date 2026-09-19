Title this pull request as a Conventional Commit — `feat:`, `fix:`, `perf:`
— when it carries release-worthy changes. This repository squash-merges
pull requests. GitHub pre-fills the merged commit's header from the pull
request title, or from the single commit's message on a one-commit branch.
Write both with the type. Any other header merges green but releases
nothing.

## Summary

-

## Test Plan

- [ ] The Swift check — `Scripts/diagnose.sh` on a macOS runner — is green on this pull request.

## Privacy / Security

- [ ] No secrets, local databases, seed files, signing keys, or credential files are included.
- [ ] Any change to audio, transcript egress, Keychain, permissions, or clipboard behavior is described above.
