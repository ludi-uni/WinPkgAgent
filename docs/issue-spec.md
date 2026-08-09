# Writing an Agent-Ready Issue

Use the [agent task template](../.github/ISSUE_TEMPLATE/agent-task.md), [bug template](../.github/ISSUE_TEMPLATE/bug_report.md), or [feature template](../.github/ISSUE_TEMPLATE/feature_request.md). An Issue is agent-ready only after a human has reviewed the final specification.

## Record outcomes, not the conversation

ChatGPT conversation is useful for exploring options, but the Issue must contain only the final agreed specification. Exclude rejected approaches, abandoned ideas, speculative additions, and contradictory conversation history. If historical context matters, summarize why the chosen behavior is required without reintroducing discarded alternatives as requirements.

## Goal is not implementation

**Goal** describes the observable outcome and user or system value. It should not prescribe file names, classes, libraries, or algorithms unless those are genuine constraints. Implementation details can prematurely narrow the solution and conflict with what the repository actually supports.

Use **Requirements** for mandatory behavior and **Constraints** for approved technical or operational limits. If a specific implementation is truly mandatory, state why it is a constraint.

## Make Acceptance Criteria mechanical

Each criterion should be independently pass/fail and observable through a test, command, response, UI behavior, artifact, or reviewable property. Prefer statements such as:

- “Given an expired session, the endpoint returns the documented unauthorized status.”
- “The existing supported test suite passes and a regression test covers the reported input.”

Avoid subjective criteria such as “works well,” “is clean,” or “is fast.” When performance matters, name the workload, environment assumptions, metric, and threshold. Do not claim a verification command exists until repository configuration confirms it.

## State Constraints and Out of Scope

**Constraints** capture compatibility, supported environments, security rules, performance limits, approved dependencies, and boundaries that implementation must preserve. **Out of Scope** prevents adjacent improvements from becoming accidental work. Explicit exclusions help an agent keep a small diff and avoid unrelated refactoring.

## Classify Risk

Choose exactly one risk level:

- `low`: small fixes, tests, types, docs, or small internal refactors;
- `medium`: features, multi-module changes, dependencies, or new APIs; or
- `high`: breaking changes, migrations, auth, secrets, deployment, infrastructure, or security-sensitive behavior.

Medium risk requires an Implementation Plan. High risk requires explicit human approval before implementation; assignment alone is not approval. If uncertain, choose the higher level and explain the concern.

## Resolve Open Questions

Do not label or assign an Issue as agent-ready while material Open Questions remain. Replace the section with `None` only after decisions are incorporated consistently into Requirements, Acceptance Criteria, Constraints, or Out of Scope. An agent must stop rather than resolve an ambiguity that materially affects behavior, safety, compatibility, or scope.

## Specify Verification from evidence

Name expected tests or checks only after inspecting the derived repository's real manifests and documentation. Do not assume a package manager, language, test runner, or build tool. Include expected manual verification when automation is impractical, while keeping criteria observable.

## Readiness checklist

- [ ] Goal states an outcome rather than an implementation preference.
- [ ] Requirements contain only final decisions.
- [ ] Acceptance Criteria are objective and testable.
- [ ] Constraints and Out of Scope are explicit.
- [ ] Verification matches tools that actually exist.
- [ ] Risk has exactly one justified level.
- [ ] Open Questions is `None` and all material ambiguity is resolved.
- [ ] No rejected or unapproved proposal is presented as a requirement.
