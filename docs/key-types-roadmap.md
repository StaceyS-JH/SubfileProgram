# Key Types Roadmap (Practical Expansion Plan)

## Purpose
Provide a practical, low-risk roadmap for expanding key type support beyond the current JWT signing focus.

This plan is aligned to the current codebase and separates:
- what you already support,
- what can be added with small changes,
- what requires new API/program paths.

## Current Baseline (Today)
Current implementation is optimized for JWT signing with asymmetric keys.

Supported generation path:
- RSA key pairs via GENKEY
- ECC key pairs via GENKEY (including Ed variants in current selector values)

Current user prompts:
- KAPMT provides key generation algorithm choices
- ALGPMT provides JWT signing algorithm choices

Current signing path:
- JWTGEN signs tokens with supported JWT algorithms and keystore private keys

## Guiding Principle
Only add new prompt options when backend generation/usage is ready.

If a new key type appears in F4 but cannot be generated or consumed by runtime code, users will get confusing behavior.

## Recommended Phased Approach

## Phase 1: Harden and Standardize Existing JWT Key Types
Scope:
- Keep key creation focused on RSA and ECC options already in GENKEY
- Keep JWT issuance focused on currently supported JWT algorithms

Improvements:
- Keep naming guidance for key labels (function prefix + suffix)
- Improve help text in KAPMT to explain intended use per option
- Add quick compatibility notes in docs (for example RS256 uses RSA private key)

Why first:
- Delivers immediate clarity with minimal risk
- No new crypto API surface required

## Phase 2: Add Purpose-Aware Choices for Existing Types
Scope:
- Continue using RSA/ECC key generation, but improve operator intent capture

Suggested prompt enhancements:
- Show intended use examples in KAPMT entries:
  - RSA2048 (JWT RS/PS signing)
  - ECC_P256 (JWT ES256 signing)
  - ECC_ED25 (EdDSA signing where applicable)
- Add optional function/purpose input in Generate Key prompt
- Keep labels policy-based (no extra table required)

Why this phase:
- Better usability without changing core cryptographic calls

## Phase 3: Symmetric Key Support (If Needed)
Scope:
- Add symmetric key workflows for non-JWT use cases (encryption/HMAC)

Typical uses:
- HMAC message authentication
- Data encryption with symmetric keys
- Key wrapping scenarios

Impact:
- Requires new generator/usage program paths
- Likely requires separate prompt flow or clearly separated algorithm family in KAPMT
- Should not be mixed into JWTGEN unless your JWT architecture moves to HS* algorithms

Risk note:
- Symmetric key lifecycle and access policy differ from asymmetric JWT signing keys

## Phase 4: Advanced Enterprise Key Uses (Optional)
Scope:
- Key agreement, envelope encryption, key wrapping/unwrapping workflows

Impact:
- New APIs, new operational controls, and stronger auditing requirements
- Better treated as a separate feature track from JWT signing

## What to Keep Separate
For maintainability, keep these concerns separate:
- JWT signing key lifecycle (current focus)
- General-purpose encryption/authentication keys

This avoids overloading LSTKSRCD/KAPMT with too many mixed-purpose options.

## Practical Recommendation for Your Project
Recommended order:
1. Finalize naming convention and usage guidance for existing RSA/ECC flows.
2. Expand KAPMT descriptions and user help before adding new key families.
3. Add new key families only when a complete end-to-end usage path exists.

In other words:
- Improve operator guidance now,
- expand cryptographic families later and intentionally.

## Readiness Checklist Before Adding Any New Key Type
- Generation API path exists and is tested
- Runtime consumption path exists and is tested
- Prompt text clearly explains intended use
- Error handling messages are user-friendly
- Documentation updated with examples and limitations

## Related Files
- src/GENKEY.RPGLE
- src/JWTGEN.RPGLE
- src/KAPMT.RPGLE
- src/KAPMT.DSPF
- src/ALGPMT.RPGLE
- src/ALGPMT.DSPF
- src/LSTKSRCD.RPGLE
- src/LSTKSRCD.DSPF

## Related Documents
- docs/key-label-prefix-proposal.md
- docs/manual-vs-maintenance-flow.md
- docs/jwt-issuance-wrapper-proposal.md
- docs/jwtcfg-active-selection-approach.md

---
Prepared for review: April 12, 2026
