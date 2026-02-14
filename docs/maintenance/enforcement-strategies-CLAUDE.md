# Enforcement Strategies for CLAUDE.md Compliance

**Status**: Decision phase (BMAD)
**Date**: 2026-02-14
**Agent**: Claude

---

## Problem Statement

CLAUDE.md contains critical directives (BMAD M.A.D.A workflow, no code changes before plan approval), but agents currently **ignore them** because:

1. **No technical enforcement** — CLAUDE.md is documentative, not exécutive
2. **Cognitive priority clash** — task description ("fix the bug") dominates over directive in context
3. **No pre-commit gates** — agents can commit/push without validating BMAD compliance
4. **Git hooks not active** — `.git/hooks/` has only samples, no real enforcement

### Example Failure
Task: "Fix UnboundLocalError in digest_selector.py"
Expected: Create story → plan → wait for approval → implement
Actual: Read code → fix → commit → push (skipped phases 1-2)

---

## Proposed Enforcement Strategies

### Strategy 1: Git Pre-Commit Hook (Lowest friction, high effectiveness)

**What**: `pre-commit` hook that blocks commits missing story/bug documentation

**Mechanics**:
```bash
.git/hooks/pre-commit
├── Check if commit touches code files
├── Look for corresponding story/bug/maintenance doc
├── If missing AND not trivial (whitespace-only), reject commit
└── Provide helpful message: "Create docs/stories/... or docs/bugs/..."
```

**Pros**:
- ✅ Works at git level (all agents)
- ✅ Low friction (just add file before committing)
- ✅ Self-enforcing (can't push without it)
- ✅ Easy to implement in shell

**Cons**:
- ❌ Agents can bypass with `git commit --no-verify` (but we forbid that in CLAUDE.md)
- ❌ Needs tuning for what counts as "trivial"

**Effort**: ~2 hours (edge cases)

---

### Strategy 2: Claude Code Hook (Startup Validation)

**What**: A shell script that runs at agent startup and enforces CLAUDE.md reading

**Mechanics**:
```bash
.claude/hooks/session-start.sh
├── Read CLAUDE.md into a temp summary
├── Print visible WARNING: "CLAUDE.md loaded. You MUST:"
│   ├── Follow BMAD M.A.D.A
│   ├── Create story/bug/maintenance doc BEFORE coding
│   ├── Wait for approval before committing
├── Require agent to acknowledge (or exit session)
```

**Pros**:
- ✅ High visibility (forces agent attention at startup)
- ✅ No git bypasses possible
- ✅ Can enforce for all session types

**Cons**:
- ❌ Requires Claude Code hook support (check availability)
- ❌ One-time per session (agent might forget by mid-session)
- ❌ Depends on session-start-hook skill

**Effort**: ~1 hour (if hook exists)

---

### Strategy 3: Pre-Commit + Startup (Hybrid, most robust)

**What**: Combine strategies 1 + 2 for belt-and-suspenders

**Mechanics**:
1. Startup hook prints BMAD workflow warning
2. Pre-commit hook enforces story/bug document exists
3. Both can reference CLAUDE.md sections for clarity

**Pros**:
- ✅ Catches agents at multiple checkpoints
- ✅ Startup hook for early awareness
- ✅ Pre-commit hook for final gate

**Cons**:
- ❌ Requires both technologies to work
- ❌ More setup time

**Effort**: ~3 hours total

---

### Strategy 4: CLAUDE.md Update (Stronger language + checklist)

**What**: Rewrite the "Before ANY Code Change" section with explicit **gates** and a mandatory checklist

**Mechanics**:
Add to CLAUDE.md:
```markdown
### ⛔ MANDATORY GATE: Before You Code

Before writing **any** code (even 1-liners), complete these steps:

□ Read CLAUDE.md entirely (check understanding of tech stack + BMAD)
□ Classify your task: Feature → docs/stories/ | Bug → docs/bugs/ | Maintenance → docs/maintenance/
□ Create the documentation file with BMAD template
□ Document your implementation_plan.md in the file
□ **STOP HERE. Wait for human approval.**
□ Only after approval: Implement (Act phase)
□ Create verification script (Verify phase)
□ Commit with story link

**If you skip these, you will need to revert and restart.**
```

**Pros**:
- ✅ No technical dependencies
- ✅ Uses existing CLAUDE.md authority
- ✅ Makes expectations crystal clear

**Cons**:
- ❌ Still relies on agent compliance (no technical gate)
- ❌ Agents might still ignore (as happened today)

**Effort**: ~30 min (documentation only)

---

## Recommendation

**Start with Strategy 3 (Hybrid)** — most comprehensive:

1. **Phase 1 (immediate)**: Implement Strategy 4 (update CLAUDE.md with explicit gates + checklist)
2. **Phase 2 (if Strategy 4 fails)**: Add Strategy 1 (pre-commit hook) for git-level enforcement
3. **Phase 3 (if available)**: Add Strategy 2 (startup hook) for session-level warning

This gives us:
- 📖 Clear, written expectations (CLAUDE.md)
- 🚫 Git-level enforcement (pre-commit)
- ⚠️ Session-level awareness (startup hook, if available)

---

## Decision Required

**Q: Which strategy should we implement?**
- A: Strategy 1 only (pre-commit hook)
- B: Strategy 3 (hybrid: startup + pre-commit)
- C: Strategy 4 only (documentation + checklist)
- D: All three (max enforcement)
- E: Something else

**Q: Should we also create a `.claude/hooks/session-start.sh` if it doesn't exist?**

---

## Files Affected

### If we choose Hybrid (Strategy 3):

```
facteur/
├── CLAUDE.md                                 (update: explicit gates)
├── .git/hooks/pre-commit                     (create: story/bug check)
└── .claude/hooks/session-start.sh            (create: CLAUDE.md summary + acknowledge)
```

### Implementation order:
1. Update CLAUDE.md (30 min)
2. Create pre-commit hook (1.5 hours)
3. Create session-start hook (1 hour)

---

*Awaiting human decision before proceeding to Act phase.*
