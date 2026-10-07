# Claims: what a sentence about an outside system rests on

What a sentence about a system this repository does not control may rest on.
Such a system may be the operating system, a framework, a client, a
service, the code host, the harness, a dependency's behaviour or a published
specification. People install, configure and choose on these sentences, and
fires act on the ones in the fleet's own documents.

Its readers:

- the agent police judges the fleet's own documents by it, and the court
  tries those findings by it;
- `.agents/rules/text-residue.md` protects the citations it requires.

## The one test

> Could a reader who acts on this sentence find, beside it, the source it
> rests on and the revision it was true at?

Fluent, confident, unsourced text is the easiest kind to produce and the
hardest to catch in review. It reads exactly like the sourced kind.

## The rules

1. **A claim names its source where it stands.** Never only in a commit
   message or a review thread. Per fact, it names the source's kind:
   documentation, source code, or a run of the system's own code.
2. **The sourcing order is the run law's** (`.agents/rules/unattended.md`,
   "Environment facts and blocked sources"). This file adds nothing to it.
3. **A claim names the revision it was true at**: a commit permalink, a tag
   or a version. A link into a moving branch dates nothing. A calendar date
   never stands in for the revision.
4. **A claim with no source beside it is treated as not yet written**,
   whoever wrote it.
5. **Never invent a command.** Never write a command, flag, endpoint or field
   that was neither run nor found in the system's documentation. Where it
   could not be verified, write none and say why. A gap is visible. A
   plausible command that does not exist is not.
6. **Keep "the standard says" apart from "this system does".** Quote the
   first from the specification, with its clause number. Attribute the
   second to the system's own documentation or source, at its revision.
7. **A supported-surface list is a list of obligations.** A row is added
   when a source backs it. It is removed when the source stops backing it.
8. **A value a machine writes is cited, never restated.** A claim about a
   released artifact points at the machine-written record, the artifact's
   own output, or the tag it was measured against. Prose never restates a
   version, digest or size that a release writes. Nothing in the release path
   corrects such prose, so the next release falsifies it in silence.
9. **A run names what it ran**: the system and its revision. A sentence that
   only reports what someone ran on one machine is not a claim to keep. It
   belongs in a report, a pull request or a caller.

## Not a defect

- **A silent source.** A requirement this repository sets that goes further
  than its source, and contradicts none, is not a defect. A statement of
  fact about the system still needs its own source.
- **A value a release writes** (`.agents/rules/boundaries.md`, "Closed
  paths"). A wrong one is judged at the release job, never in the text.
- **A claim whose source is blocked.** The check is reported as not run
  (`.agents/rules/unattended.md`, "Environment facts and blocked sources"),
  never as a finding.
- **A caution that names no system.** A hazard stated as a possibility, such
  as "some routes replace the set", claims nothing about one system. The run
  law's hazards are written this way on purpose.

## Neighbours

Which role owns a claim follows `.agents/rules/filing.md`, "Ownership
routing".
