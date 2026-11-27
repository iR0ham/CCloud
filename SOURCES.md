# Source and License Provenance

This file separates verified source identities and hashes from release
provenance that remains unverified. It is not a claim that every native binary
in every artifact has been fully audited.

## Verified component sources

### code3-dev/CCloud

- Repository: https://github.com/code3-dev/CCloud
- Commit: `6db96e34a352eafa91876d32cfeb007a378894fd`
- License source: https://raw.githubusercontent.com/code3-dev/CCloud/6db96e34a352eafa91876d32cfeb007a378894fd/LICENSE
- Retained text: `Legal/licenses/MIT-code3-dev-CCloud.txt`
- Text SHA-256: `20dfbb80c78f13c6368b68f7e56d407dc18dbfab3e37b42abe450ceb9a5c8fc4`

### Vazirmatn

- Repository: https://github.com/rastikerdar/vazirmatn
- Version: 33.003
- Commit: `83629f877e8f084cc07b47030b5d3a0ff06c76ec`
- License source: https://raw.githubusercontent.com/rastikerdar/vazirmatn/83629f877e8f084cc07b47030b5d3a0ff06c76ec/OFL.txt
- Retained text: `Legal/licenses/OFL-1.1-Vazirmatn.txt`
- Text SHA-256: `17e355067c8284f47743a1ee3b1ef7ff684ff0601eda357f9353b10b3016ab31`

### media_kit packages

The pub.dev archive hashes below match `flutter_app/pubspec.lock`. Each
archive contained the same MIT `LICENSE` body. A source-code commit was not
supplied for these package versions and is not invented here.

| Package | Version | Archive URL | Archive SHA-256 |
| --- | --- | --- | --- |
| media_kit | 1.2.6 | https://pub.dev/api/archives/media_kit-1.2.6.tar.gz | `ae9e79597500c7ad6083a3c7b7b7544ddabfceacce7ae5c9709b0ec16a5d6643` |
| media_kit_video | 1.3.1 | https://pub.dev/api/archives/media_kit_video-1.3.1.tar.gz | `813858c3fe84eb46679eb698695f60665e2bfbef757766fac4d2e683f926e15a` |
| media_kit_libs_android_video | 1.3.8 | https://pub.dev/api/archives/media_kit_libs_android_video-1.3.8.tar.gz | `3f6274e5ab2de512c286a25c327288601ee445ed8ac319e0ef0b66148bd8f76c` |
| media_kit_libs_windows_video | 1.0.11 | https://pub.dev/api/archives/media_kit_libs_windows_video-1.0.11.tar.gz | `dff76da2778729ab650229e6b4ec6ec111eb5151431002cbd7ea304ff1f112ab` |

- Retained text: `Legal/licenses/MIT-media_kit.txt`
- Text SHA-256: `2e3000f38718f050869d57540c288c661a446f64df1ba4ea4764df552b04a331`

### famelack-data

- Repository: https://github.com/famelack/famelack-data
- Commit: `d97463ec4a940d6bf0c1c6c770084f77ba037133`
- License source: https://raw.githubusercontent.com/famelack/famelack-data/d97463ec4a940d6bf0c1c6c770084f77ba037133/LICENSE
- Retained text: `Legal/licenses/MIT-famelack-data.txt`
- Text SHA-256: `dfc34af32be9a99fab09f7f6ab40bcb0bf0fef561fd2276b3e4b981755e46a1c`

### iptv-org

- Repository: https://github.com/iptv-org/iptv
- Commit: `60fde4cc8c03f02b47ebe0b6373971e610081713`
- License source: https://raw.githubusercontent.com/iptv-org/iptv/60fde4cc8c03f02b47ebe0b6373971e610081713/LICENSE
- Retained text: `Legal/licenses/Unlicense-iptv-org.txt`
- Text SHA-256: `640514163b17f977adc997cb16f51871122cfb0555ebad1a3f01e167b7ba8857`

### ANGLE

- Repository: https://github.com/google/angle
- License commit: `a0ccea1e8d1f2b7620db08c7cbbac7d01cfc38d6`
- License source: https://raw.githubusercontent.com/google/angle/a0ccea1e8d1f2b7620db08c7cbbac7d01cfc38d6/LICENSE
- Retained text: `Legal/licenses/BSD-3-Clause-ANGLE.txt`
- Text SHA-256: `bf4da21bd20bcfb5b60b7ecc67fa864a79be049e21d6178076887f178dd6c71a`
- Release status: the exact bundled Windows ANGLE revision is unverified.

## GNU license texts

The GPL/LGPL bodies are authoritative GNU plain-text copies:

| Retained text | Source URL | Text SHA-256 |
| --- | --- | --- |
| `Legal/licenses/GPL-2.0.txt` | https://ftp.gnu.org/gnu/Licenses/gpl-2.0.txt | `edaef632cbb643e4e7a221717a6c441a4c1a7c918e6e4d56debc3d8739b233f6` |
| `Legal/licenses/GPL-3.0.txt` | https://ftp.gnu.org/gnu/Licenses/gpl-3.0.txt | `3972dc9744f6499f0f9b2dbf76696f2ae7ad8af9b23dde66d6af86c9dfb36986` |
| `Legal/licenses/LGPL-2.1.txt` | https://ftp.gnu.org/gnu/Licenses/lgpl-2.1.txt | `20e50fe7aae3e56378ebf0417d9de904f55a0e61e4df315333e632a4d3555d95` |
| `Legal/licenses/LGPL-3.0.txt` | https://ftp.gnu.org/gnu/Licenses/lgpl-3.0.txt | `e3a994d82e644b03a792a930f574002658412f62407f5fee083f2555c5f23118` |

## Native-media evidence and unresolved provenance

### macOS FFmpeg

- Inspected version: Homebrew FFmpeg 8.1.2_1.
- Reported license: GPLv3-or-later.
- Inspected executable SHA-256:
  `8375ea085870e99fc0bd000f09a60d294875158d69f42bb992b56f3f19607550`.
- Researcher-supplied source tarball SHA-256:
  `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`.
- Unverified: the hosted workflow uses unpinned `brew install ffmpeg`, so a
  release-specific binary/source identity is not yet captured.

### Android mpv and FFmpeg

- mpv commit: `78d43740f52db817d98bcf24fb30a76ab6fa13ff`.
- mpv configuration: `-Dgpl=false` (LGPLv2.1+).
- FFmpeg version: 6.0.
- FFmpeg configuration: `--disable-gpl --disable-nonfree --enable-version3
  --enable-static --disable-shared` (LGPLv3).
- Linkage: FFmpeg is statically linked into `libmpv.so`.
- Missing evidence: relinkable objects and a verified relinking procedure.

### Windows native media

- Wrapper: `media_kit_libs_windows_video` 1.0.11, whose pub.dev archive
  SHA-256 is `dff76da2778729ab650229e6b4ec6ec111eb5151431002cbd7ea304ff1f112ab`
  (the verified row in the media_kit table above).
- Upstream-attested mpv source commit (a 40-hex git SHA-1, not an archive
  checksum): `652a1dd90711839acdccc08004056d25514ef2d8`. The wrapper states it
  in `CHANGELOG.md` and encodes it in the archive name
  `mpv-dev-x86_64-20230924-git-652a1dd.7z`.
- Attested binary archive:
  `https://github.com/media-kit/libmpv-win32-video-build/releases/download/2023-09-24/mpv-dev-x86_64-20230924-git-652a1dd.7z`.
  The only integrity field the wrapper publishes for it is the MD5 download
  check `a832ef24b3a6ff97cd2560b5b9d04cd8`, recorded here as-is. A SHA-256 of
  the downloaded archive was not independently captured.
- Default mpv license: GPLv2+.
- Inferred FFmpeg recipe: `--enable-gpl --enable-version3 --enable-nonfree`.
- Missing evidence: independent confirmation that the shipped bytes were built
  from the attested commit, the full build inputs of
  `libmpv-win32-video-build`, a complete DLL inventory, and a complete
  corresponding source package. Naming an upstream candidate commit does not
  satisfy the corresponding-source obligation.

## Evidence boundary

No repository-wide license, written offer, corresponding-source archive, or
Android relinking procedure is asserted by this file. Those artifacts must be
created only after the underlying native-media obligations are resolved and
the exact release provenance is captured.
