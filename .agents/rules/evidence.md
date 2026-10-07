# Evidence and judged rounds

How a claim is proved in every adversarial round: police triage, the
court's trial, the spec reviewer's review, and the implementer's acceptance
round. A role that convenes a round names this file and never restates it.

- **An exhibit** is a quoted `path:line` at the commit under judgement, or a
  command with its verbatim output. Where nothing can be compiled or run, a
  code path traced with every step quoted is the exhibit for "this can
  happen".
- **An assertion without an exhibit is struck.** It cannot support a
  verdict. The judge lists what it struck.
- **The judge re-checks one exhibit itself**: the single most decisive one.
  If it does not hold, the verdict may not rest on it.
- **Every participant is a sub-agent with a clean context.** It receives
  paths, never the convener's reasoning. It sees no other participant's
  brief or output outside the shared record. It writes only under `$RUN`.
- **A brief is neutral.** It carries no confidence, no effort spent, no
  count of other candidates and no hint of the wanted answer. The convener
  vets every brief, and a leading brief is rewritten or refused.
- **A round has a ceiling on sub-agents**, stated by the role that convenes
  it. The ceiling is a hard stop: a round that would pass it stops and says
  so. A seat that answers again in a later step counts once.
