# ساخت از سورس — CCloud برای macOS

این مخزن، سورس کامل نسخهٔ نیتیو macOS اپلیکیشن CCloud است (SwiftUI + AppKit، بدون هیچ وابستگی خارجی).
هدف: با یک دستور، همان `CCloud.app` قابل ساخت و اجرا باشد.
نسخهٔ Windows از همان اپ در `flutter_app/` (Flutter) ساخته می‌شود — بخش ۸.

---

## ۱. پیش‌نیازها

| مورد | توضیح |
|---|---|
| macOS | ۱۵ (Sequoia) یا جدیدتر، Apple Silicon (arm64) |
| Swift toolchain | **Command Line Tools** کافی است: `xcode-select --install` (نیازی به Xcode کامل نیست) |
| ffmpeg (اختیاری) | فقط برای پخش MKV در **زمان ساخت بسته**؛ اگر نصب باشد با `scripts/bundle_ffmpeg.sh` داخل اپ کپی می‌شود. نبودنش مانع ساخت نیست (اپ به ffmpeg سیستم/HOMEBREW/PATH برمی‌گردد). |
| Homebrew (اختیاری) | فقط برای گرفتن ffmpeg: `brew install ffmpeg` |

بررسی سریع ابزارها:

```bash
swiftc --version && xcrun --show-sdk-path && which ffmpeg
```

## ۲. ساخت اپ

```bash
cd CCloudMac-2.0.0-source   # پوشهٔ همین سورس
./build.sh                  # خروجی: build/CCloud.app  (امضای ad-hoc)
./build.sh --run            # ساخت + اجرا
```

اسکریپت `build.sh` همهٔ `Sources/**/*.swift` را با `swiftc` کامپایل می‌کند، `Resources/` را داخل
`Contents/Resources` کپی می‌کند، `Info.plist` را می‌گذارد و اپ را امضای ad-hoc می‌کند.

گزینه‌های مفید هنگام کار موازی/آزمایشی:

```bash
CCLOUD_OUT=$PWD/build-dev ./build.sh        # خروجی در پوشهٔ دیگر
./scripts/typecheck.sh                      # فقط بررسی تایپ (سریع)
```

## ۳. دارایی‌های تولیدی (اختیاری)

این‌ها از قبل در `Resources/` هستند یا با اسکریپت دوباره ساخته می‌شوند:

```bash
./scripts/make_icon.sh        # ساخت Resources/AppIcon.icns از لوگوی اپ (CoreGraphics + iconutil)
./scripts/bundle_ffmpeg.sh    # کپی ffmpeg + کتابخانه‌هایش به Resources/ffmpeg-bin/ (خودکفا، @loader_path)
```

> فونت‌های وزیرمتن و لوگوها (`Resources/Fonts/*.ttf`, `Resources/logo*.png`) در مخزن هستند.
> پوشهٔ `Resources/ffmpeg-bin/` به‌خاطر حجم (۳۷ مگابایت) در سورس نیست؛ با اسکریپت بالا ساخته می‌شود.
> بدون آن هم اپ کار می‌کند و از ffmpeg نصب‌شده استفاده می‌کند.

## ۴. تست‌ها

```bash
./Tests/api/run.sh             # ۳۰ تست زندهٔ API (نیازمند اینترنت)
./Tests/player/run.sh          # ۱۱۹ تست موتور پخش با مدیای محلی (ffmpeg لازم دارد)
./scripts/qa_snapshots.sh --all # ۱۹ اسکرین‌شات از همهٔ صفحات (خروجی در qa/)
./scripts/qa_smoke.sh          # بررسی بسته، آیکون، فونت، ffmpeg، امضا، اجرا، API
./scripts/make_dist.sh         # ساخت dist/CCloud-macOS.zip + SHA-256
```

اسکرین‌شات‌ها با قلاب داخلی اپ گرفته می‌شوند (ترمینال `screencapture` در بعضی محیط‌ها مجاز نیست):

```bash
./build/CCloud.app/Contents/MacOS/CCloud --snapshot /tmp/shot.png --snapshot-delay 12 --tab movies
# گزینه‌ها: --tab movies|series|live|search|favorites|countries|settings
#           --demo movie|series|country|search|about|live|live-channels|live-play
#           --demo player-local /path/to/file.mp4 --debug-player-controls --debug-scroll-bottom
```

## ۵. ساختار پروژه

```
Sources/
  App/      CCloudApp.swift (entry) · AppState · Theme (فونت/رنگ) · Components · RootView (سایدبار/روتر)
  Core/     Models · APIClient (کاتالوگ CCloud) · LiveTVClient + LiveTVModels (پخش زنده) · Stores (علاقه‌مندی/تنظیمات)
  Player/   PlaybackController · RemuxSession · HLSServer · PlayerSurface (AVPlayer + ffmpeg→HLS)
  UI/
    Browse/ MoviesView · SeriesView · SearchView · FavoritesView · CountriesView · CountryDetailView
    Detail/ MovieDetailView · SeriesDetailView · SettingsView · AboutView · SplashView · PlayerScreen
    Live/   LiveTVView (کشورها → شبکه‌ها → پخش زنده)
Resources/  Fonts (وزیرمتن) · AppIcon.icns · logo*/png · ffmpeg-bin/ (تولیدی)
Tests/      api (هارنس زندهٔ API) · player (هارنس موتور پخش + مدیای تولیدی)
scripts/    typecheck · make_icon · bundle_ffmpeg · qa_* · make_dist
```

## ۶. نکات فنی مهم

1. **`@State` استفاده نمی‌شود.** Command Line Tools اپل، پلاگین ماکروی SwiftUI را همراه ندارد و
   `@State` کامیایل نمی‌شود؛ به‌جای آن از `@StateObject` + مدل‌های `ObservableObject` و
   `Binding(get:set:)` استفاده شده است (جزئیات در `PROJECT.md` §۵.۵).
2. **فونت‌ها** در `CCloudApp.init()` قبل از اولین رندر ثبت می‌شوند؛ اگر دیرتر ثبت شوند، اسپلش و
   نوار کنار با فونت جایگزین سیستم رسم می‌شوند (باگ قبلی که رفع شد).
3. **MKV:** AVPlayer ماتروسکا را نمی‌خواند؛ موتور پخش با ffmpeg فایل را روی همان دستگاه به HLS
   (fMP4) تبدیل و از یک HTTP server لوکال پخش می‌کند. برای seek دور، ffmpeg با `-ss` ری‌استارت می‌شود.
4. **باندل و امضا:** شناسهٔ باندل `ir.ccloud.macapp` است. اپ ad-hoc امضا می‌شود (بدون notarization)؛
   برای اولین اجرا: راست‌کلیک → Open یا `xattr -dr com.apple.quarantine /Applications/CCloud.app`.
5. **اولین باندل با همین شناسه:** macOS به نسخهٔ دوم یک باندل در حال اجرا پنجره نمی‌دهد؛ برای تست‌های
   موازی از `--snapshot` استفاده کنید و بین اجراها مطمئن شوید نمونهٔ قبلی بسته شده است.
6. **پخش زنده:** دادهٔ آن از مجموعهٔ باز Famelack (جانشین TV Garden) روی GitHub خوانده می‌شود؛
   اسکیما: `sources.streams` و همهٔ استریم‌ها HLS/HTTPS هستند. فهرست «ایران» همان ۶۲ شبکهٔ famelack
   است و پلی‌لیست iptv-org (`countries/ir.m3u`، `languages/fas.m3u`) فقط لینک یدک به آن شبکه‌ها
   اضافه می‌کند؛ ادغام در `LiveTVCatalog` انجام می‌شود و تطبیق نام با `LiveTVNameKey`.
   دسترسی به CDNها به شبکه/جغرافیا بستگی دارد و خطای پخش با پیام فارسی + گزینهٔ VLC/کپی لینک نمایش داده می‌شود.

## ۷. عیب‌یابی ساخت

| خطا | راه‌حل |
|---|---|
| `error: cannot find 'State'` یا خطای ماکروی SwiftUI | از `@State` استفاده شده؛ طبق §۶.۱ با `@StateObject` جایگزین کنید |
| `xcrun: error: unable to find utility "xcodebuild"` | طبیعی است؛ ما با `swiftc` می‌سازیم. فقط `xcrun --show-sdk-path` لازم است |
| اپ بدون پنجره باز می‌شود (`windows=0`) | نسخهٔ دیگری از همان bundle id در حال اجراست؛ همه را ببندید |
| پخش MKV شروع نمی‌شود | `Resources/ffmpeg-bin/ffmpeg` را با `bundle_ffmpeg.sh` بسازید یا `brew install ffmpeg` |
| «برنامه از توسعه‌دهندهٔ شناسایی‌شده نیست» | ad-hoc امضاشده؛ راست‌کلیک → Open |

## ۸. نسخهٔ Windows (Flutter)

نسخهٔ Windows از همان کد Flutter در `flutter_app/` ساخته می‌شود، نه از `Sources/` نیتیو macOS.
ساخت cross-compile از مک ممکن نیست؛ بیلد روی ویندوز یا runner ویندوزی CI انجام می‌شود.

### اجرای نسخهٔ منتشرشده

| مورد | توضیح |
|---|---|
| ویندوز | **ویندوز ۱۰ ۶۴بیتی یا جدیدتر**. ویندوز ۱۰ نسخهٔ ۱۶۰۷ (Build 14393) و بالاتر توصیه می‌شود؛ `flutter_windows.dll` به `api-ms-win-core-path-l1-1-0.dll` وابسته است که روی ۱۵۰۷/۱۵۱۱ و LTSB 2015 ممکن است موجود نباشد و برنامه بدون هیچ پنجره‌ای بسته شود. |
| Visual C++ | **لازم نیست جداگانه نصب شود.** `msvcp140.dll`، `vcruntime140.dll` و `vcruntime140_1.dll` داخل ZIP/نصب‌کننده هستند. |
| استخراج | ZIP را **کامل** استخراج کنید و `ccloud.exe` را از داخل فایل ZIP اجرا نکنید؛ همهٔ DLLها و پوشهٔ `data` باید کنار exe باشند. |
| SmartScreen | چون بسته امضای تجاری ندارد، ویندوز ممکن است هشدار «Windows protected your PC» بدهد؛ «More info → Run anyway» یا در Properties گزینهٔ Unblock. |
| نصب‌کننده | فایل `CCloud-1.0.7-windows-x64-setup.exe` در `%ProgramFiles%\CCloud` نصب می‌کند، شورت‌کات استارت‌منو و (اختیاری) دسکتاپ می‌سازد و در Add/Remove Programs ثبت می‌شود. نسخهٔ ZIP همان فایل‌ها را بدون نصب اجرا می‌کند. |
| بستهٔ سازگاری | اگر بیلد عادی پنجره نشان نداد، ZIP با پسوند `-compat` را امتحان کنید: همان برنامه با رندرر Skia به‌جای Impeller. در نسخهٔ ZIP می‌توانید کنار `ccloud.exe` یک فایل خالی به نام `compat.txt` بگذارید و برنامه را دوباره اجرا کنید؛ همین اثر را دارد. |

### عیب‌یابی راه‌اندازی

runner ویندوز حالا هر مرحله از راه‌اندازی را در این فایل ثبت می‌کند:

```text
%LOCALAPPDATA%\CCloud\startup.log
```

خط‌های آن شامل نسخه، نتیجهٔ ساخت پنجره، ساخت engine/view، اولین فریم، خروج و هر خطا
همراه با `GetLastError` است. اگر پنجره نیامد، اول همین فایل را بخوانید. شکست ساخت پنجره یا
engine و همچنین نرسیدن اولین فریم تا ۱۵ ثانیه، یک پیام خطای ویندوزی با مسیر لاگ هم نشان
می‌دهد؛ دیگر هیچ شکستی بی‌صدا نیست.

### ساخت

پیش‌نیازهای ماشین ساخت:

| مورد | توضیح |
|---|---|
| Flutter | ۳.۴۷.۸ (stable) روی `PATH` |
| Visual Studio 2022 | workload «Desktop development with C++» (CMake + MSVC) |
| اینترنت | اولین بیلد، آرشیوهای libmpv/ANGLE را برای `media_kit_libs_windows_video` دانلود می‌کند |

بیلد محلی (PowerShell):

```powershell
.\build_windows.ps1
```

یا دستی:

```powershell
cd flutter_app
flutter pub get
flutter build windows --release
```

خروجی: `flutter_app\build\windows\x64\runner\Release\` شامل `ccloud.exe`، `libmpv-2.dll`،
DLLهای ANGLE و پوشهٔ `data`. **سه DLL رانتایم VC++ به‌طور خودکار کنار exe کپی نمی‌شوند؛**
برای پکیج قابل انتقال آن‌ها را از `VC\Redist\MSVC\*\x64\Microsoft.VC143.CRT` بردارید
(workflow همین کار را می‌کند). نبودشان باعث می‌شود برنامه بدون هیچ پیامی اجرا نشود.

ساخت با CI: workflow «Build Windows» در `.github/workflows/build-windows.yml` — اجرای دستی از تب
Actions (workflow_dispatch) یا push یک tag با الگوی `v*`. خروجی‌ها:

- `CCloud-windows-x64` — پوشهٔ Release با DLLهای VC++ (ZIP قابل انتقال).
- `CCloud-windows-x64-compat` — فقط اگر SDK فعلی کلید Impeller را داشته باشد؛ همان بسته با Skia.
- `CCloud-windows-x64-setup` — نصب‌کنندهٔ Inno Setup؛ اگر Inno روی runner پیدا/نصب نشود،
  این مرحله با هشدار skip می‌شود و بیلد قرمز نمی‌شود.

این مرحله publish/release نمی‌کند. version در `pubspec.yaml` هم باید با شمارهٔ ریلیز یکی باشد
(اکنون `1.0.7+8`) تا در Properties فایل exe و صفحهٔ About دیده شود.

## ۹. اعتبارها

- اپ اندروید اصلی: <https://github.com/code3-dev/CCloud> (Kotlin/Compose)
- نسخهٔ Flutter دسکتاپ (منبع بخش پخش زنده): `CCloud-GUI`
- دادهٔ شبکه‌های زنده: <https://github.com/famelack/famelack-data> (پیش‌تر TV Garden)
  و فهرست مکمّل <https://github.com/iptv-org/iptv>
- فونت وزیرمتن (SIL OFL) · FFmpeg (GPL، فقط فایل اجرایی همراه بسته)
