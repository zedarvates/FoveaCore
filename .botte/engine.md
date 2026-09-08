# Pinned Botte rule auditor

The three Python modules below are unmodified copies from the public Botte
Secrète [PR #103](https://github.com/zedarvates/botte-secrete/pull/103) at
[`e121ea16cbd5a772ddb485414928c0938eace2d5`](https://github.com/zedarvates/botte-secrete/commit/e121ea16cbd5a772ddb485414928c0938eace2d5).
They require only Python 3.10+ and the standard library; no bootstrap,
provider, project import, shell probe, network or installation is involved.
The upstream [MIT license](engine-LICENSE.txt) is retained.

| File | SHA-256 |
|---|---|
| `skills/console_utf8.py` | `80e0583b55e816b85193238abcca6f16ae84d38c382b792763e0f5e90e662eb5` |
| `skills/directives_audit/rules.py` | `6af048fa89d1214d21e5abb2a82144ebfde26bf9bfaec120a3f91ead61e18284` |
| `skills/directives_audit/rules_cli.py` | `28da4117cd51bd12f7392857bf82b144895353b44d04c5f4d378968e4347fea7` |

## Verification boundary

The initial rule review checked the exact source wording, deterministic guard
implementations and both accept/reject test anchors. Each semantic receipt
binds those rule fields, including owner boundaries and replacement edges.
An empty `supersedes` list intentionally introduces no replacement edges.

`botte.rules-audit/v1` checks references and semantic receipts. It never runs
tests or proves their outcome. A receipt timestamp is a source-review date,
not a runtime or CI result. The fingerprint is independent of the checkout
directory, but does not bind all repository bytes or assert the Git SHA.
Execution evidence therefore requires the exact checked-out commit separately.

Require `manifest_present: true`, at least one rule, and zero errors and
warnings before accepting the registered contract. A missing manifest or
execution receipt remains BLOCKED. This initial manifest does not cover all
project policies, hardware behavior or publishing decisions.

Update the pinned engine deliberately; never download a moving branch during
an audit or silently regenerate semantic receipts after policy changes.
