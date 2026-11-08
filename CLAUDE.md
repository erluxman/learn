# CLAUDE.md

## "Rate it" protocol (every project, any language)

When I say "rate it" / "rate this" / "re-rate", review the latest work with this protocol.
Don't ask me which criteria or experts; pick this project's personas and competitor yourself and state them.

### Expert panel (each scores independently; use a subagent that didn't build the work when possible)
1. End-user personas - 2-3 real target users of this project (e.g. YouTube creator, Keynote presenter).
2. QA / usability tester - tries to break it: edge cases, regressions; writes a manual test checklist for me.
3. UX / visual designer - fidelity, typography, consistency, motion, visual polish.
4. Accessibility specialist - WCAG 2.2 AA: keyboard, screen reader, contrast, target size, reduced motion.
5. Staff engineer / architect - design fit, complexity, coupling, maintainability, test quality.
6. Security engineer - threat model, OWASP Top 10 / ASVS L2: authz on every path, injection, secrets, deps, PII.
7. Performance / SRE engineer - performance budgets, observability, rollout and rollback.
8. Independent devil's advocate - misuse, failure scenarios, unstated assumptions.
Skip an expert only if clearly irrelevant to the work, and say why.

### Parameters (each 1-10)
1. Correctness & completeness - meets acceptance criteria / passing conditions, edge cases, nothing stubbed.
2. Polish & UX - visual finish; feedback; empty/loading/error states; copy; no clipped labels; platform conventions.
3. Ease of use & accessibility - discoverable, few steps, keyboard, WCAG 2.2 AA, respects reduced motion.
4. Competitor parity - side by side vs a named best-in-class app on the same axes; list gaps vs competitor.
5. Performance - vs explicit budget (16.7ms frames, input <100ms, LCP<=2.5s INP<=200ms CLS<=0.1); give numbers.
6. Reliability & security - failure modes, no data loss, recovery, input handling, secrets, authorization.
7. Code quality & tests - design, simplicity, naming; tests that would fail if the code broke; CI green.
8. Verified evidence & ops - run in the real app (screenshots/GIF, test counts, benchmarks); logs, rollback, docs.

### Scoring rules
- Target is 9+. Anchors: 10 exemplary; 9 ship-ready, at or above best-in-class; 7-8 solid, minor gaps;
  5-6 works with notable debt; 3-4 significant defects; 1-2 broken.
- Weakest view wins: a parameter's score is the lowest any relevant expert gives it.
- Overall = weighted mean (Correctness & completeness counts double), then apply gate caps.
- Gates (cap overall): core acceptance failure or data loss -> 4; critical security issue -> 3;
  build/CI red or no tests for new logic -> 5; unhandled crash or silent failure -> 5;
  breaking change without migration -> 5; WCAG blocker on core flow -> 6;
  >2x over perf budget or visible jank -> 6; never run in the real app (code-read only) -> 7.
- 9+ requires every gate passed, no parameter below 8, and evidence behind every score.
- Never claim what wasn't verified; list what wasn't tested. Rate the work, not the effort. Don't inflate.
- Re-rating: same strictness every round; show the trail (round 1 -> now); explain any drop; flag regressions.

### Output
1. Header: what was rated, competitor, personas, round number.
2. Scoreboard table: parameter | score | competitor score | lowest-scoring expert + one-line reason.
3. Panel table: expert | score | top finding.
4. Gates: pass/fail each. Then Overall /10 (with trail on re-rates).
5. Checklist met / missing (with file:line).
6. "To reach 9" - most important first, each with cause and concrete fix.
7. Gaps vs competitor, corner cases, manual test checklist I can run.
8. Not verified list, then a one-sentence verdict.
For multi-feature reviews, also publish an HTML artifact dashboard (bands 9+/8/6-7/4-5/<4, priority filter).
Offer to file a "Follow-ups to reach 9" GitHub issue.
