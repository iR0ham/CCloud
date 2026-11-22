#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <chrono>
#include <string>
#include <thread>

#include "flutter_window.h"
#include "startup_log.h"
#include "utils.h"

#ifndef CCLOUD_VERSION
#define CCLOUD_VERSION "unknown"
#endif

namespace {

// True when |name| exists next to ccloud.exe. The path comes from the module
// itself, never from the working directory, so a shortcut or "Run as
// administrator" cannot hide compat.txt.
bool FileExistsNextToExe(const wchar_t* name) {
  wchar_t exe_path[MAX_PATH * 2];
  const DWORD length = ::GetModuleFileNameW(
      nullptr, exe_path, static_cast<DWORD>(sizeof(exe_path) / sizeof(wchar_t)));
  if (length == 0 ||
      length >= static_cast<DWORD>(sizeof(exe_path) / sizeof(wchar_t))) {
    return false;
  }
  std::wstring path(exe_path, length);
  const size_t slash = path.find_last_of(L"\\/");
  if (slash == std::wstring::npos) {
    return false;
  }
  path.resize(slash + 1);
  path += name;
  const DWORD attributes = ::GetFileAttributesW(path.c_str());
  return attributes != INVALID_FILE_ATTRIBUTES &&
         (attributes & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

}  // namespace

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  StartupLog(std::string("start: CCloud ") + CCLOUD_VERSION +
             " (Windows runner)");

  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  // Renderer escape hatch. The default release keeps the Flutter default
  // (Impeller); a compat.txt next to the exe or a CCLOUD_FORCE_SKIA build turns
  // it off, because a broken GPU/driver path can otherwise leave a hidden
  // window. The switch is compiled only when the configured SDK provides it.
  const bool compat_requested = FileExistsNextToExe(L"compat.txt");
  bool compat = compat_requested;
#ifdef CCLOUD_DEFAULT_SKIA
  compat = true;
#endif
#ifdef CCLOUD_HAS_IMPELLER_SWITCH
  if (compat) {
    project.set_impeller_switch(flutter::ImpellerSwitch::Disabled);
    StartupLog("renderer: Impeller disabled (compat build or compat.txt)");
  } else {
    StartupLog("renderer: Impeller default");
  }
#else
  if (compat) {
    StartupLog(
        "renderer switch unavailable in this SDK; the compat request was "
        "ignored");
  } else {
    StartupLog("renderer switch unavailable in this SDK");
  }
#endif

  // If the window or the renderer wedges, the process must not stay alive as
  // an invisible background task. A slow disk or an antivirus scan can delay a
  // healthy start, so after 15 seconds keep checking once a second up to 30
  // seconds and only report when no frame has arrived by then. This only
  // reports; it never forces Show().
  std::thread([]() {
    std::this_thread::sleep_for(std::chrono::seconds(15));
    for (int extra = 0; extra < 15 && !HasFirstFrame(); ++extra) {
      std::this_thread::sleep_for(std::chrono::seconds(1));
    }
    if (!HasFirstFrame()) {
      ShowFirstFrameWarning();
    }
  }).detach();

  FlutterWindow window(project);
  Win32Window::Point origin(10, 10);
  Win32Window::Size size(1280, 720);
  if (!window.Create(L"CCloud", origin, size)) {
    const DWORD error = ::GetLastError();
    StartupLog("ERROR: window.Create returned false (GetLastError=" +
               std::to_string(error) + ")");
    if (!StartupErrorShown()) {
      ShowStartupError("The main window could not be created.", error);
    }
    return EXIT_FAILURE;
  }
  StartupLog("window created");
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  StartupLog("quit: message loop exited");
  ::CoUninitialize();
  return EXIT_SUCCESS;
}
