# Context: precedence and the writing standard

Which text wins when two disagree, and the standard every document that
instructs an agent is written to: `AGENTS.md` and every rule file under
`.agents/rules/`.

## Precedence

When two texts disagree, this order decides.

1. The owner's recorded decisions, quoted in `AGENTS.md` or a rule file.
2. The repository is right about the work. The caller is right about the
   machine it runs on.
3. A rule file that describes something else is stale when the thing it
   describes disagrees. Something else is a CI pipeline, a configuration
   file, the label list or an outside specification. The described thing
   wins, and the rule file is fixed.
4. A rule file MAY name, in its first paragraph, the rule files it yields
   to. Two rule files that contradict each other, where neither yields, have
   no automatic winner. The owner decides. An order fixed in advance would
   settle a contradiction nobody has read.

Every rule file that describes something outside itself ends with that
staleness clause, naming what it describes.

## Writing rules

1. One topic per file, plain language, English, plain Markdown.
2. Front matter only where a rule genuinely applies to part of the tree. A
   rule with no front matter loads unconditionally, which is the safe
   default.
3. Path scoping is a consumer-side hint, and some consumers ignore or misread
   it. Nothing load-bearing is ever scoped. A scoped rule must pass this
   test: if no consumer ever loads it, nothing breaks.
4. A rule references only these:
   - other rule files;
   - `AGENTS.md`;
   - stable documents, such as `docs/architecture.md`.

   A rule never references a requirements document, a pull request, an
   issue, another temporary file or a code location. They move, and the
   rule rots with them. A temporary document may cite a rule. The reverse is
   forbidden.
5. A rule never restates `AGENTS.md` or another rule file. It points at the
   file that owns the fact and adds only what that file lacks.
6. Every rule is checkable against the tree. A rule describing a practice
   the repository does not follow is a defect. An intention is labelled as
   one.
7. Every mechanical check states beside itself the clause or failure mode it
   enforces. A check with neither is ceremony and is deleted.
8. Shared bounds, vocabularies and grammars live once, in the rule file that
   owns them. Other documents name them and restate no number.
9. Never write a rule that constrains tooling the run does not control,
   such as a footer a harness appends after publication. The run cannot
   keep such a rule, so it fails on every run.
10. Prose in instructions is load-bearing. Tie each sentence to its
    condition: a stop sentence that opens with "Then" reads as a step after
    every case, not as a stop for one.
11. A document names a repository file by its path from the repository
    root, never by a bare filename or a path relative to itself. A bare
    filename points a fire at a path it cannot resolve.
12. A sentence about an outside system follows `.agents/rules/claims.md`:
    its source, the source's kind and its revision stand beside it.

## The context standard

- **No neutral information.** Text that does not help a reader act costs
  attention and hides the useful parts. Ask of every line: does a reader
  who acts on this need it?
- **No dates in text that instructs an agent.** An owner's decision is
  attributed as the owner's, with no day. A date format is written as a
  format (`YYYY-MM-DD`), never as an example. Quoted data and
  machine-written trees keep their dates.
- **The action, never the instrument.** A sentence that tells a role what
  to do states the action, never which client, tool, harness or route does
  it. The same action may be done through a command-line client, a harness
  tool or a person by hand. Attribution is another matter: which model and
  tool produced a text may be named (`AGENTS.md`, "Standing owner
  directives", 13).
  Nameable at the edge of a rule:
  - the repository's own substrate: version control, the Swift package
    manager, the scripts under `Scripts/` and the pipeline definitions under
    `.github/workflows/`;
  - a spelling named to forbid it.
- **One word for what fires a role: "caller".** A harness's own word for a
  scheduled trigger, such as "routine" or "scheduled task", is not used. A
  caller includes a person. A prohibition aimed at fired agents names the
  role or the stage, never the caller, or it forbids the owner's own act.
- **Three kinds of fact belong to the caller** and never to the repository:
  - the measured facts of an environment;
  - the clone sequence;
  - the cadence.

  A role that needs one reads it from the caller. A caller that carries none
  is a report line, and every check that depended on it is not run.
- **Personal preferences of the owner are not repository rules.** A role
  reads every sentence as an instruction, so a preference written here acts
  as a rule.
