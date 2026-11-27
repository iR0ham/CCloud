# Distribution Status

Production publication requires both the existing signing gates and a
`DISTRIBUTION-<platform>.txt` value of exactly `production-approved`. Current
values are deliberately conservative. Signing never substitutes for
redistribution permission.

| Platform | Required current label | Status and blocking evidence |
| --- | --- | --- |
| macOS | `INTERNAL-ONLY-PENDING-SOURCE-MATERIAL` | Internal-only. The inspected Homebrew FFmpeg 8.1.2_1 is GPLv3-or-later, but the hosted workflow is unpinned. Pin and record the release-specific FFmpeg binary and corresponding source inventory before production redistribution. |
| Android | `INTERNAL-ONLY-BLOCKED-RELINKING` | Internal-only. mpv is LGPLv2.1+ and statically linked FFmpeg 6.0 is LGPLv3. Relinkable objects and a verified relinking procedure are absent. |
| Windows | `INTERNAL-ONLY-BLOCKED-GPL-NONFREE` | Internal-only. The pinned wrapper references a default GPLv2+ mpv archive and an inferred GPL/nonfree FFmpeg recipe. Exact build provenance, complete DLL inventory, and corresponding source package are unverified. |
| webOS | `INTERNAL-ONLY-PENDING-DEVICE-ACCEPTANCE` | Notice packaging can be verified in the IPK data archive. Device installation and runtime acceptance remain unverified. |

## Release rule

The release workflow must set `publish=false` with explicit reasons whenever
any platform label is missing or differs from `production-approved`. Internal
artifacts may be retained for inspection, but they must not be published as a
production release.

## Evidence boundary

There is no verified written offer, corresponding-source archive, or Android
relinking procedure in this repository. No placeholder file is used to imply
otherwise. Resolving a blocker requires new evidence and an explicit status
change; it cannot be accomplished by changing a label alone.
