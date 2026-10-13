# Plan Mode

## Prerequisites

Complete **Inspect** first (or reuse a fresh inspect report).

## Steps

1. Load `capabilities/catalog.yml`.
2. Map requested goals to capabilities: Required / Recommended / Optional / Not applicable.
3. Apply existing-vs-new rules from `agent/CICD.agent.md`:
   - reuse / extend / minimal new / fix-before-replace
4. Build a **configuration matrix** with independent dimensions:
   - app/platform, environment, build configuration, market/flavor/variant,
     distribution destination, trigger, signing strategy, runner/toolchain
5. Include portable patterns only when useful and project-configurable:
   - presets/variants JSON
   - optional config overrides
   - thin entry → reusable workflow (GitHub Actions)
6. Present phased implementation with dependencies. Do not require later phases to finish earlier independent phases.
7. List prerequisites with purpose, owner, status, verification method, and fallback.
8. For Jenkins: state contract status from `docs/JENKINS.md` — plan concrete Jenkins work as a later phase unless already approved.

## Output

One consolidated proposal:

- Recommended reuse vs changes
- Capability matrix for this project
- File-level change list (kit and/or target)
- Prerequisites and blockers
- Validation plan
- Explicit approval request (scope boundaries: no commit/push/dispatch/secrets/distribution unless listed)

Do not implement until approved.
