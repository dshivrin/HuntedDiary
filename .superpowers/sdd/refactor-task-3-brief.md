## Task 3: Add cryptographic request capabilities

**Files:**
- Create: `Shortcuts/DiaryReplyCapability.swift`
- Create: `TheHuntedDiaryTests/Shortcuts/DiaryReplyCapabilityTests.swift`

- [ ] Test 32-byte secure token generation, base64url round-trip, malformed handles, lowercase/uppercase UUID parsing, SHA-256 storage, constant-time comparison behavior, and redacted descriptions.
- [ ] Implement `DiaryReplyCapability.generate()` using a system CSPRNG; never `UUID`, `RandomNumberGenerator` assumptions, or timestamps for the secret.
- [ ] Define strict maximum handle length and reject whitespace, extra separators, duplicate fields, and invalid base64url.
- [ ] Verify logs/errors expose only the request UUID prefix, never the capability.

