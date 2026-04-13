# JWT Issuance Wrapper Proposal

## Objective
Reduce hard-coded values in application code while keeping JWT generation flexible and maintainable.

Current pain points:
- Calling JWTGEN directly requires many parameters.
- Teams may hard-code all claims, keystore details, or a single JWT label.
- Subject handling can become inconsistent across applications.

This proposal introduces a stable wrapper API and configuration-driven resolution so application code passes minimal runtime data.

## Proposed Design
Create a new program (example name: JWTISSUE) as the primary API for application developers.

JWTISSUE responsibilities:
1. Resolve configuration profile (which JWTLABEL to use) from caller input/context.
2. Resolve subject using explicit input, derivation rules, or profile defaults.
3. Retrieve signing configuration from JWTCFG (via GETJWTCFG or internal SQL).
4. Call JWTGEN with resolved values.
5. Return token + status/message to caller.

JWTGEN remains the cryptographic engine and is not removed.

## Why This Helps
- Eliminates hard-coding of keystore/key/algorithm/claims in many callers.
- Keeps app code stable during key rotation and config changes.
- Centralizes validation, governance, and error handling.
- Supports both human-user and machine-to-machine token scenarios.

## Recommended Caller Contract
Minimal input model for application code:
- ProfileId (or ClientId/UseCase)
- Subject (optional)
- Optional override claims (Audience, JTI)

Output model:
- JwtOut
- ResultCode
- ResultMsg

Resolution behavior:
1. If Subject passed: use it.
2. If not passed: derive from rule/context.
3. If still missing: use profile default subject (machine profile only).
4. If unresolved: fail with clear error.

## Subject Strategy (Avoid Hard-Coding)
Subject should normally be runtime data, not source-code constants.

Preferred order:
1. Explicit runtime subject from caller transaction/session.
2. Derived subject rule based on context (for example job user, client id, principal id).
3. Profile-level default subject for system/service tokens only.

Examples:
- Human flow: subject = authenticated user id/email.
- B2B flow: subject = external principal/account id.
- Service flow: subject omitted by caller, resolved to profile default service identity.

## Profile Resolution Strategy (Avoid Hard-Coded JWTLABEL)
Use a lookup chain instead of embedding a label in each app:
1. Caller-passed ProfileId (recommended explicit key)
2. App/context mapping (program, user, service consumer)
3. Environment default profile
4. Fail with diagnostic if no match

This allows tokens to be issued without app-level JWTLABEL constants in most cases.

## Suggested Data Model Enhancements
Keep current JWTCFG table and add mapping/governance where needed.

Suggested mapping table (concept):
- PROFILE_ID
- JWTLABEL
- ACTIVE
- PRIORITY
- EFFECTIVE_FROM
- EFFECTIVE_TO
- DEFAULT_SUBJECT
- SUBJECT_RULE

Optional governance fields:
- ALLOW_AUD_OVERRIDE
- ALLOW_JTI_OVERRIDE
- OWNER_APP
- LAST_VERIFIED_TS

## Flow Comparison
Manual/direct flow today:
1. Caller provides all JWTGEN parameters or hard-coded JWTLABEL + extra lookup logic.
2. Caller owns claim population and consistency.

Proposed wrapper flow:
1. Caller sends minimal inputs to JWTISSUE.
2. JWTISSUE resolves profile + subject + defaults.
3. JWTISSUE calls GETJWTCFG/JWTGEN.
4. Caller receives token and status.

## Validation and Guardrails
Centralize these checks in JWTISSUE:
- Required fields resolved (profile, key label, algorithm, issuer, subject as policy requires)
- Algorithm/key compatibility
- Expiry bounds (for example minimum and maximum allowed)
- Override authorization (who can override audience/JTI)

## Audit and Operations
Add operational logging for each issuance request:
- Caller identity/program
- Resolved profile and JWT label
- Algorithm and key label
- Outcome (success/failure), code, timestamp

Operational benefits:
- Easier diagnostics
- Better governance and traceability
- Safer rotations and rollback

## Rotation and Change Management
Support safe key/profile rotation with configuration only:
- Introduce new JWTLABEL/profile mapping as active with effective dates.
- Keep old profile active during overlap if needed.
- Cut over by mapping priority/date, not code deployment.

## Phased Implementation Plan
Phase 1 (low risk):
1. Build JWTISSUE wrapper with minimal contract.
2. Reuse GETJWTCFG and JWTGEN.
3. Add clear ResultCode/ResultMsg semantics.

Phase 2:
1. Add profile mapping table and profile resolution hierarchy.
2. Add subject derivation/default logic.

Phase 3:
1. Add audit logging and policy checks.
2. Add admin visibility (where-used, active profile checks, test-sign feature).

## Backward Compatibility
- Keep JWTGEN callable for diagnostics and advanced/manual use.
- Mark JWTISSUE as the preferred integration API for application developers.
- Existing manual scripts continue to work.

## Recommendation
Adopt JWTISSUE as the standard entry point for application teams.

Policy guidance:
- Applications should not directly hard-code keystore, key label, algorithm, or static JWTLABEL in normal integrations.
- Subject should come from runtime identity data whenever possible.
- Use defaults only for service/machine profiles where a fixed subject is intentional.

## Review Checklist
Use this checklist during design review:
- Does caller contract minimize required inputs?
- Is subject resolution deterministic and documented?
- Are profile fallback rules explicit and safe?
- Are overrides policy-controlled?
- Is audit logging sufficient for support/compliance?
- Is JWTGEN still available for manual diagnostics?

## Related Documentation
- docs/jwtcfg-active-selection-approach.md
- docs/key-label-prefix-proposal.md
- docs/key-types-roadmap.md
- docs/manual-vs-maintenance-flow.md
- docs/program-call-map.md

---
Prepared for review: April 12, 2026
