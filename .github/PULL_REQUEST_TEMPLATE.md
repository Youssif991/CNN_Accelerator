## Summary

Describe the problem or feature, the root cause, and what this change
accomplishes. Include any relevant context about design decisions,
trade-offs, or prior art.

If this change fixes a bug, explain the conditions that triggered it and
how the fix prevents it. If this is a feature, briefly outline the
motivation and the intended user-facing behavior.

> **Related PRs** — List any related pull requests by number and explain
> how they relate (depends on, conflicts with, refactors the same area,
> etc.). If none, write *N/A*.

---

## Target branch

All PRs land in `main`. If your PR targets a different branch, click
"Edit" on this PR and change the base.

---

## Linked Issue

Fixes #\<issue-number\>

If no issue exists, write *N/A* and briefly explain why this change was
handled directly.

---

## Type of Change

Select all that apply:

- [ ] Bug fix (non-breaking — fixes a confirmed issue)
- [ ] New feature (non-breaking — adds new behaviour)
- [ ] Breaking change (changes or removes existing behaviour)
- [ ] Refactor / cleanup (behaviour unchanged)
- [ ] Documentation only
- [ ] CI / tooling / configuration

---

## Checklist

- [ ] I searched open issues and open PRs — this is not a duplicate.
- [ ] This PR targets `main`.
- [ ] My changes are limited to the scope described above — no unrelated
      refactors or whitespace changes mixed in.
- [ ] I ran the simulation / tooling and verified the change works
      end-to-end. Unit tests alone are not sufficient.

---

## How to Test

Provide step-by-step instructions for testing this change.

**Simulation commands:**

```bash
# Example: run a specific testbench
make all TB_FILE=tb/tb_<module>.v

# Example: run all testbenches via CI script
./scripts/run_ci.sh
```

**Key scenarios to verify:**

1. List the specific test cases or waveforms to check.
2. Describe the expected output or behaviour for each scenario.
3. Mention any edge cases that were explicitly tested.

---

## Visual / UI changes

N/A — this repository contains RTL design and simulation artefacts only;
no UI rendering changed.

- [ ] Screenshot or waveform capture of the change, attached below.
- [ ] Style match: the change uses the project's existing coding style.
- [ ] No new module patterns. If a similar module already exists, extend
      it instead of writing a parallel one.
- [ ] I am not an LLM agent submitting a bulk PR. If you are, please open
      an issue describing the problem first — bulk auto-generated PRs
      that do not match the project's coding style are closed on sight.

---

## Screenshots / clips

Attach simulation waveform screenshots, console output logs, or RTL
schematic captures that demonstrate the change working correctly.

*If no visual changes apply, write N/A.*
