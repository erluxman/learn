# CLAUDE.md

## "Rate it" convention

When I say **"rate it"** (or "rate this", "give it a rating"), rate the most recent
piece of work in the conversation (code, a plan, a doc, a design, an answer)
using the rubric below. Don't ask me which criteria to use — use these.

### Rubric (each scored 1–10)

| # | Criterion | What it means |
|---|-----------|---------------|
| 1 | **Correctness** | Does it actually work / is it factually right? Bugs, edge cases, wrong assumptions. |
| 2 | **Completeness** | Does it fully solve what was asked, or are pieces missing / stubbed? |
| 3 | **Clarity & readability** | Easy to understand? Good naming, structure, and explanation. |
| 4 | **Simplicity** | No over-engineering, no needless abstraction or duplication. |
| 5 | **Robustness** | Error handling, failure modes, security, performance where relevant. |
| 6 | **Maintainability** | Easy to change later? Fits existing conventions of the project. |
| 7 | **User value / UX** | Does it serve the end user well (for apps: feel, polish, accessibility)? |

Skip a criterion only if it truly doesn't apply, and say "N/A" for it.

### Scoring scale

- **9–10** — Excellent, ship it as-is.
- **7–8** — Good, minor improvements possible.
- **5–6** — Works but has clear weaknesses.
- **3–4** — Significant problems.
- **1–2** — Broken or off-target.

### Output format

1. A table with each criterion, its score, and a one-line reason.
2. **Overall score** out of 10 (weighted: Correctness and Completeness count double).
3. **Top 3 improvements**, ordered by impact, each concrete and actionable.
4. One-sentence verdict.

Be honest and critical — don't inflate scores. Rate the work, not the effort.
