# Agent Policy and Responsibility Model

## Why this template exists

This template makes agent-assisted development reviewable and conservative. It does not treat an AI agent as an autonomous owner of a repository. Instead, it assigns each participant a narrow role and preserves human control over consequential decisions.

> **Do not trust the agent; trust the verification process the agent must pass.**

An agent's confidence or completion claim is never sufficient. Structured requirements, tests, CI output, a bounded diff, and human review provide the evidence.

## Roles in the workflow

### ChatGPT: specification front end

ChatGPT helps a human explore the problem, identify constraints, expose ambiguity, and turn the final decisions into a structured Issue. Conversation is a drafting space, not an authoritative specification. Rejected ideas and unresolved alternatives must not leak into an agent-ready Issue.

### GitHub Issue: specification checkpoint

The assigned Issue is the fixed, reviewable source of task scope. It records the Goal, Requirements, Acceptance Criteria, Constraints, Out of Scope, Verification, Risk, and Open Questions. Humans should resolve material Open Questions before assigning work. Changes to scope should be made explicitly in the Issue rather than passed informally to an agent.

### Codex or coding agent: implementation role

The coding agent investigates the repository, makes the smallest in-scope change, adds tests, runs supported checks, and self-reviews its diff under [`AGENTS.md`](../AGENTS.md). It must stop at ambiguity or elevated-risk boundaries rather than make consequential product, security, or operational decisions.

### CI: objective verification

CI repeats deterministic checks outside the agent's narrative. A derived repository should replace the minimal template validation with real test, lint, type-check, build, and format checks supported by its stack. Branch protection should require the relevant checks.

### Draft Pull Request: agent exit

A Draft Pull Request is the agent's delivery boundary. It links the Issue and presents the changes, exact verification commands, results, risk, and remaining concerns. Draft status communicates that the work still needs human judgment; it is not permission to merge or deploy.

### Human: final approval and merge

A human owns specification approval, high-risk authorization, review, readiness decisions, and the final merge. Agents must never push to the default branch, enable auto-merge, merge their own Pull Requests, operate production, or handle secrets.

## Risk and approval gates

- **Low:** small bug fixes, tests, type fixes, documentation, or small internal refactors can normally proceed to a Draft Pull Request.
- **Medium:** features, multi-module work, dependency changes, or new APIs require a concise Implementation Plan. Any explicit Issue approval gate must be honored.
- **High:** breaking changes, migrations, authentication/authorization, secrets, deployment, infrastructure, and security-sensitive work require explicit, auditable human approval before implementation.

Approval does not override absolute boundaries: an agent still does not deploy to production, manipulate secrets, push directly to the default branch, auto-merge, or merge.

## Stop rather than guess

Implementation stops when requirements conflict, material interpretations differ, Open Questions remain, safety cannot be demonstrated, or the change expands unexpectedly. Database migrations, auth changes, security policy changes, production infrastructure, credentials, breaking APIs, and substantial CI/CD changes also require human direction. The agent may report findings and propose options, but it must not silently choose a specification.

## Repository and workflow security

GitHub Actions must declare least-privilege permissions. Third-party actions must be reviewed and pinned to immutable commit SHAs, and untrusted code must not receive secrets. Derived repositories should configure protected branches, required human review, required status checks, and disabled auto-merge as appropriate to their GitHub plan and governance.

## Evidence expected in a Draft PR

The reviewer should be able to map the diff to every Acceptance Criterion, inspect relevant tests, reproduce exact verification commands, see any unavailable check honestly identified, and confirm that no unrelated work is mixed in. The Issue and Pull Request must link to one another.
