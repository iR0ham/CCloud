<div dir="rtl" align="right">

<img src="Resources/logo.png" width="88" alt="CCloud">

# CCloud — کلاینت استریم چندپلتفرمی

مجموعهٔ **غیررسمی** کلاینت‌های CCloud برای macOS، ویندوز، اندروید (گوشی/تبلت/Android TV) و تلویزیون‌های LG webOS.
هر چهار نسخه همان کاتالوگ زنده را مرور و همان منابع را پخش می‌کنند: فیلم‌ها، سریال‌ها، جست‌وجو،
فیلتر کشور و ژانر، پخش زنده، علاقه‌مندی‌ها و پخش‌کنندهٔ داخلی.

> **English:** Unofficial multi-platform CCloud streaming clients — a native SwiftUI/AppKit app for
> macOS, a Flutter desktop app for Windows, a Flutter app for Android phones, tablets and Android TV,
> and an HTML/JS client for LG webOS. All share the same catalog, live-TV dataset and Persian RTL interface.

## 📱 پلتفرم‌ها

| پلتفرم | تکنولوژی | نسخه | مسیر |
|---|---|---|---|
| macOS | SwiftUI + AppKit (بدون وابستگی خارجی) | 2.0.0 | `Sources/` |
| Windows 10/11 (x64) | Flutter (Dart) + media_kit | 1.0.6 | `flutter_app/` |
| Android / Android TV | Flutter (Dart) + media_kit | 1.0.6 | `flutter_app/` |
| LG webOS TV | HTML/CSS/JS + سرویس Node | 1.0.0 | `webos_app/` |

## ⬇️ دانلود

همهٔ بسته‌ها در [Releases](https://github.com/iR0ham/CCloud/releases) هستند و از این مخزن ساخته می‌شوند؛
هیچ فایل اجرایی در خود مخزن commit نمی‌شود.

| بسته | آخرین انتشار |
|---|---|
| **Windows** — `CCloud-Windows-1.0.6-x64.zip` | [windows-1.0.6](https://github.com/iR0ham/CCloud/releases/tag/windows-1.0.6) |
| macOS — `.dmg` / `.zip` (2.0.0) | [v2026.11.10](https://github.com/iR0ham/CCloud/releases/tag/v2026.11.10) |
| Android — `CCloud-Android-1.0.6.apk` | [v2026.11.10](https://github.com/iR0ham/CCloud/releases/tag/v2026.11.10) |
| LG webOS — `com.ccloud.tv_1.0.0_all.ipk` | [v2026.11.10](https://github.com/iR0ham/CCloud/releases/tag/v2026.11.10) |

برای ویندوز فایل ZIP را استخراج کنید و `CCloud-windows-x64\ccloud.exe` را اجرا کنید (DLLها باید کنار
فایل اجرایی بمانند). این بیلد امضای دیجیتال ندارد؛ اگر SmartScreen هشدار داد: More info ← Run anyway.
سایدبار و شیت About در هر پلتفرم به‌صورت خودکار نام همان سیستم‌عامل را نشان می‌دهد
(«نسخه ویندوز»، «نسخه اندروید»، «نسخه مک (macOS)»).

## ✨ امکانات

- **کاتالوگ زنده:** فیلم‌ها و سریال‌ها با صفحه‌بندی بی‌پایان، فیلتر ژانر و مرتب‌سازی (جدیدترین / سال / IMDb)
- **جست‌وجو** در کل کاتالوگ
- **پخش زنده:** بیش از ۶٬۰۰۰ شبکهٔ تلویزیونی از ۱۷۲ کشور، با جست‌وجوی کشور و شبکه
- **کشورها:** مرور فیلم‌ها و سریال‌ها و پخش زندهٔ هر کشور
- **صفحهٔ جزئیات:** کاور، پوستر، سال، IMDb، مدت، ژانرها، توضیحات و فهرست کیفیت‌ها/منابع
- **سریال‌ها:** انتخاب فصل و فهرست قسمت‌ها با پخش جداگانه
- **پخش‌کنندهٔ داخلی:** پخش/توقف، ±۱۰ ثانیه، نوار زمان، صدا، سرعت، انتخاب کیفیت و تمام‌صفحه
- **علاقه‌مندی‌ها و تاریخچهٔ تماشا** (بسته به پلتفرم)
- **نسخهٔ دسکتاپ (macOS و ویندوز):** ادامهٔ تماشا با دقت ثانیه، میانبرهای کیبورد و پلیر داخلی بدون پنجرهٔ جدا
- **رابط کامل فارسی و راست‌به‌چپ** با فونت وزیرمتن، تم تیره
- پشتیبانی از `mp4`، `m3u8` و `mkv` (روش پخش در هر پلتفرم متفاوت است)

## 🗂 ساختار مخزن

<div dir="ltr">

```
CCloudMac/
├── Sources/        # macOS app (SwiftUI + AppKit)
├── Resources/      # fonts, icons, logos
├── Tests/          # macOS API and player test harnesses
├── scripts/        # build, QA, icon, release scripts
├── flutter_app/    # Android phone/tablet/TV + Windows desktop
├── webos_app/      # LG webOS TV client + Node service
├── .github/workflows/ # Windows CI (build + runtime smoke test)
├── build.sh        # macOS build script
├── build_windows.ps1 # Windows build script (local)
├── Info.plist      # macOS bundle metadata
├── PROJECT.md      # macOS architecture and interfaces
└── BUILD.md        # macOS build guide (Persian)
```

</div>

پوشه‌های `build/`، `.dart_tool/`، `dist/`، `qa/`، `Resources/ffmpeg-bin/` و فایل‌های APK در مخزن
نیستند (در `.gitignore`)؛ همه با اسکریپت‌های همین پروژه دوباره ساخته می‌شوند.

## 🛠 ساخت و اجرا

### macOS

نیازمندی‌ها: macOS 15 یا جدیدتر، Apple Silicon، و Command Line Tools (`xcode-select --install`).
نیازی به Xcode کامل نیست؛ پروژه با `swiftc` ساخته می‌شود.

<div dir="ltr">

```bash
./build.sh          # → build/CCloud.app (ad-hoc signed)
./build.sh --run    # build + open
```

</div>

برای پخش `mkv`، ffmpeg لازم است: یا نصب‌شده در Homebrew/`PATH`، یا نسخهٔ همراه بسته:

<div dir="ltr">

```bash
./scripts/bundle_ffmpeg.sh   # copies ffmpeg + libs into Resources/ffmpeg-bin/
```

</div>

جزئیات بیشتر (تست‌ها، اسکرین‌شات QA، ساخت بستهٔ توزیع) در [BUILD.md](BUILD.md).

### Windows

ویندوز را نمی‌شود از macOS کراس‌کامپایل کرد؛ مسیر رسمی، workflow
[Build Windows](.github/workflows/build-windows.yml) روی `windows-latest` است که با هر push تگ `v*`
یا اجرای دستی، سه job «Dart analyze»، «Windows release build» و «Windows runtime smoke test» را اجرا می‌کند
و artifactهای `CCloud-windows-x64` و `windows-smoke-evidence` را می‌سازد.

برای بیلد محلی روی ویندوز ۱۰/۱۱: Flutter 3.47.8 روی `PATH` و Visual Studio 2022 با workload
«Desktop development with C++».

<div dir="ltr">

```powershell
powershell -ExecutionPolicy Bypass -File .\build_windows.ps1
# → flutter_app/build/windows/x64/runner/Release/ccloud.exe
```

</div>

نسخهٔ نمایش‌داده‌شده در UI از `package_info_plus` می‌آید (نه عدد ثابت در کد) و version resource فایل اجرایی
در `flutter_app/windows/runner/Runner.rc` از همین متغیرهای نسخهٔ `pubspec.yaml` ساخته می‌شود.

### Android / Android TV

نیازمندی‌ها: Flutter SDK با Dart 3.13 یا جدیدتر، Android SDK.

<div dir="ltr">

```bash
cd flutter_app
flutter pub get
flutter run                        # debug on a device / emulator
flutter build apk --release        # → build/app/outputs/flutter-apk/app-release.apk
flutter build apk --release --split-per-abi
```

</div>

- اپ روی گوشی، تبلت و Android TV اجرا می‌شود (لانچر leanback و بنر TV در `AndroidManifest.xml`).
- اگر فایل `flutter_app/android/key.properties` وجود داشته باشد، بیلد release با همان کلید امضا می‌شود؛
  در غیر این صورت امضای debug استفاده می‌شود. **کلید امضا و رمزهای آن در این مخزن نیستند.**
- گزینهٔ `usesCleartextTraffic` برای پخش منابع `http` روشن است. پخش با media_kit (libmpv) انجام می‌شود.

### LG webOS

نیازمندی‌ها: LG webOS TV در حالت Developer Mode، و ابزارهای webOS CLI (`ares-*`) از
`@webos-tools/cli`.

<div dir="ltr">

```bash
cd webos_app
npm start            # local dev server → http://localhost:8080
npm run package      # ares-package app service/com.ccloud.tv.service -o dist
ares-install --device <tv-name> dist/com.ccloud.tv_1.0.0_all.ipk
```

</div>

اپ یک سرویس Node همراه دارد (`service/com.ccloud.tv.service`) که درخواست‌های کاتالوگ و دادهٔ پخش زنده را
برای مرورگر تلویزیون fetch می‌کند و مشکل CORS را دور می‌زند. `npm start` همین کار را با یک پروکسی
محلی برای تست در مرورگر دسکتاپ انجام می‌دهد.

## 🌐 داده‌ها و شبکه

- **کاتالوگ:** از API سرویس CCloud خوانده می‌شود. کلاینت‌ها سه میزبان جایگزین را به‌ترتیب امتحان
  می‌کنند و در صورت شکست، میزبان بعدی را انتخاب می‌کنند. صفحه‌ها ۰-based و هر صفحه ۳۰ آیتم است.
- **پخش زنده:** فهرست کشورها و شبکه‌ها از مجموعهٔ باز
  [Famelack Data](https://github.com/famelack/famelack-data) (جانشین TV Garden) و پلی‌لیست
  مکمل [iptv-org](https://github.com/iptv-org/iptv) ساخته می‌شود. منبع اصلی famelack است و iptv-org
  فقط لینک‌های جاافتاده را اضافه می‌کند. فهرست ایران دقیقاً همان ۶۲ شبکهٔ famelack است.
- منابع ویدیو با `http` روی CDNهای مختلف میزبانی می‌شوند؛ به همین دلیل macOS
  (`NSAllowsArbitraryLoads`) و اندروید (`usesCleartextTraffic`) دسترسی آزاد دارند.
  بعضی منابع ممکن است در بعضی شبکه‌ها/کشورها در دسترس نباشند یا IP ایران را مسدود کنند.

## 🎬 پخش ویدیو

| پلتفرم | روش |
|---|---|
| macOS | `mp4`/`m3u8` با AVPlayer؛ `mkv` با remux محلی ffmpeg به HLS (fMP4) و پخش از HTTP سرور داخلی |
| Windows | media_kit (libmpv) — همان مسیر اندروید؛ ANGLE/D3D11 برای رندر |
| Android | media_kit (libmpv) — پشتیبانی گسترده از فرمت‌ها و HLS |
| webOS | تگ HTML5 `<video>` و کدک‌های خود تلویزیون (HLS/MP4/MKV) |

در macOS نسخهٔ خودکفای ffmpeg به‌همراه همهٔ کتابخانه‌های لازم داخل بسته قرار می‌گیرد
(`CCloud.app/Contents/Resources/ffmpeg-bin/`). این فایل اجرایی تحت مجوز **GPL** است و کد برنامه
جدا از آن است.

## 🧪 تست‌ها

<div dir="ltr">

```bash
./Tests/api/run.sh              # 30 live API tests (network required)
./Tests/player/run.sh           # 119 playback-engine tests with local media (ffmpeg required)
./scripts/qa_snapshots.sh --all # 19 screenshots of all screens (output in qa/)
./scripts/qa_smoke.sh           # bundle, icon, fonts, ffmpeg, signature, launch, API checks
./scripts/typecheck.sh          # fast Swift type check
```

</div>

## ⚠️ محدودیت‌ها و حقوق

- این مخزن یک **پورت غیررسمی** است و هیچ وابستگی سازمانی به سازندهٔ اصلی یا سرویس CCloud ندارد.
- همهٔ حقوق محتوا (فیلم، سریال، پوستر و پخش زنده) متعلق به صاحبان آن است؛ این پروژه فقط کلاینت است.
  استفادهٔ شخصی و آموزشی، و مسئولیت دسترسی به منابع بر عهدهٔ کاربر است.
- APKها، بستهٔ webOS، بستهٔ ویندوز، خروجی‌های بیلد و **کلید امضای اندروید** در مخزن نیستند؛
  باینری‌ها فقط در Releases منتشر می‌شوند. بیلد ویندوز فعلاً امضای دیجیتال ندارد (هشدار SmartScreen).
- پخش‌کننده در دسکتاپ (macOS و ویندوز) مسیر درون‌برنامه‌ای است و پنجرهٔ جدا ندارد.
- این مخزن در حال حاضر فایل `LICENSE` ندارد؛ تا اضافه‌شدن مجوز، همهٔ حقوق محفوظ است.
- ffmpeg (GPL) فقط به‌صورت فایل اجرایی در بستهٔ macOS توزیع می‌شود.

## 🙏 اعتبارها

- اپ اندروید اصلی: [code3-dev/CCloud](https://github.com/code3-dev/CCloud)
- دادهٔ شبکه‌های زنده: [Famelack Data](https://github.com/famelack/famelack-data) و
  [iptv-org](https://github.com/iptv-org/iptv)
- فونت [وزیرمتن](https://github.com/rastikerdar/vazirmatn) (SIL OFL)
- [FFmpeg](https://ffmpeg.org) (GPL) برای پخش MKV در macOS

</div>
