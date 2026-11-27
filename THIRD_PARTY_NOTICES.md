# Third-Party Notices

CCloud distributes or invokes third-party software and data. This inventory
records only identities and build facts that are supported by the evidence in
`SOURCES.md`. Full license bodies are retained under `Legal/licenses/`.

## Verified components

| Component | Version / revision | License | Copyright |
| --- | --- | --- | --- |
| code3-dev/CCloud | commit `6db96e34a352eafa91876d32cfeb007a378894fd` | MIT | Copyright (c) 2025 Hossein Pira |
| Vazirmatn | 33.003, commit `83629f877e8f084cc07b47030b5d3a0ff06c76ec` | SIL OFL-1.1 | Copyright 2015 The Vazirmatn Project Authors |
| media_kit | 1.2.6 | MIT | Copyright (c) 2021 & onwards Hitesh Kumar Saini |
| media_kit_video | 1.3.1 | MIT | Copyright (c) 2021 & onwards Hitesh Kumar Saini |
| media_kit_libs_android_video | 1.3.8 | MIT | Copyright (c) 2021 & onwards Hitesh Kumar Saini |
| media_kit_libs_windows_video | 1.0.11 | MIT | Copyright (c) 2021 & onwards Hitesh Kumar Saini |
| famelack-data | commit `d97463ec4a940d6bf0c1c6c770084f77ba037133` | MIT | Copyright (c) 2026 Famelack LLC |
| iptv-org | commit `60fde4cc8c03f02b47ebe0b6373971e610081713` | Unlicense | No copyright grant is made by the Unlicense text |
| ANGLE | commit `a0ccea1e8d1f2b7620db08c7cbbac7d01cfc38d6` | BSD-3-Clause | Copyright 2018 The ANGLE Project Authors |

The exact bundled Windows ANGLE revision is not verified. The cited ANGLE
commit identifies the license text only; it is not evidence that the same
revision is present in a release DLL.

The four media_kit package archives were hash-verified against
`flutter_app/pubspec.lock`. Their `LICENSE` files are byte-identical and are
retained once as `Legal/licenses/MIT-media_kit.txt`.

## Native media obligations and blockers

### macOS

The inspected local bundle contains Homebrew FFmpeg 8.1.2_1, identified as
GPLv3-or-later. The inspected executable SHA-256 is
`8375ea085870e99fc0bd000f09a60d294875158d69f42bb992b56f3f19607550`; the
corresponding source tarball SHA-256 supplied by the researcher is
`464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`.

The hosted workflow installs an unpinned Homebrew FFmpeg. Therefore the local
inspection is not release-specific provenance. macOS redistribution remains
internal-only until the release workflow pins and records the exact FFmpeg
identity and corresponding source material.

### Android

The Android native media stack is reported as:

- mpv commit `78d43740f52db817d98bcf24fb30a76ab6fa13ff`, built with
  `-Dgpl=false` (LGPLv2.1+).
- FFmpeg 6.0 built with `--disable-gpl --disable-nonfree --enable-version3
  --enable-static --disable-shared` (LGPLv3).
- FFmpeg statically linked into `libmpv.so`.

Relinkable objects and a verified relinking procedure are absent. Android
production redistribution is therefore blocked. This notice does not claim
that a written offer or relinking kit exists.

### Windows

The pinned `media_kit_libs_windows_video` 1.0.11 wrapper references mpv archive
SHA-256 `652a1dd90711839acdccc08004056d25514ef2d8`. The wrapper's default mpv
recipe is GPLv2+, and the inferred FFmpeg recipe enables `--enable-gpl
--enable-version3 --enable-nonfree`.

The exact mpv build commit, complete DLL inventory, and corresponding source
package are not verified. Windows production redistribution is therefore
blocked for GPL/nonfree and incomplete-provenance reasons. The MIT license of
the Dart wrapper does not change the licenses of the native libraries it
packages.

### webOS

The canonical notices and license texts are staged into the webOS application
package and asserted in the extracted data archive. Device installation and
runtime acceptance remain unverified, so webOS artifacts remain internal-only
pending device acceptance.

## Distribution control

Signing status and redistribution permission are separate. A signed artifact
is not production-approved unless its `DISTRIBUTION-<platform>.txt` label is
exactly `production-approved` and the supporting obligations have been
resolved. Current conservative labels and blockers are recorded in
`Legal/DISTRIBUTION_STATUS.md`.

No `WRITTEN_OFFER.md` or `RELINKING.md` placeholder is provided because no
compliant written offer or relinking procedure has been established.
