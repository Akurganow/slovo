# Evidence

How a claim is proved in a judged round here. The adversarial rounds of
this repository's roles follow this file; a role that judges names it
rather than restating it.

- **An exhibit** is a quoted `path:line` at the commit under judgement, or
  a command with its verbatim output. Where nothing can be compiled or
  run, a code path traced with every step quoted is the exhibit for "this
  can happen".
- **An assertion without an exhibit is struck** and cannot support a
  verdict. The judge lists what it struck.
- **The judge re-checks one exhibit itself**: the single most decisive
  one. If it does not hold, the verdict may not rest on it.
- **Every participant is a subagent with a clean context.** It receives
  paths, never the convening run's reasoning, sees no other participant's
  brief or output outside the shared record, and writes only under `$RUN`,
  never in the working tree.
- **A round has a ceiling on subagents**, stated by the role that convenes
  it. The ceiling is a hard stop: a round that would pass it stops there
  and says so in the report.
