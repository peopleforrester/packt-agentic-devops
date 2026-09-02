<!-- ABOUTME: The primary-source trail behind the platform: what was specified, what was verified -->
<!-- ABOUTME: against upstream in June 2026, and which decisions are locked and why. -->

# Reference material

These three documents were written while the platform was being built, and they are published
because the claims elsewhere in this repo lean on them. A version pin or an architectural assertion
with no traceable source is a guess, and the point of keeping these is that you can check the
working rather than take the conclusion.

| File | What it is |
|---|---|
| [`build-spec.md`](build-spec.md) | The full build specification the agent worked from, phase by phase |
| [`research-findings-june-2026.md`](research-findings-june-2026.md) | Verification of every pinned version against upstream, with the gotchas found along the way |
| [`decisions.md`](decisions.md) | Locked architectural decisions and the reasoning, including the ones later reversed |
| [`research-student-aws-scope-july-2026.md`](research-student-aws-scope-july-2026.md) | How the per-attendee AWS permission scope was derived, with sources |

Two things to read them with in mind.

**They are dated.** The research was done in June 2026 and the versions it verifies have moved since;
`versions.lock.md` and [`../version-maintenance.md`](../version-maintenance.md) carry the current
policy. Read these for *why* a choice was made, not for what to install today.

**Decisions include the reversals.** `decisions.md` records approaches that were tried and rejected,
which is the half that usually gets lost. A rejected approach leaves no trace in the code, so
without a record the next person rediscovers it, finds it plausible, and proposes it again.
