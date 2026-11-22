#include "startup_log.h"

#include <windows.h>

#include <atomic>
#include <cstdio>
#include <mutex>
#include <string>

namespace {

std::mutex g_log_mutex;
std::atomic<bool> g_error_shown{false};
std::atomic<bool> g_first_frame{false};

// %LOCALAPPDATA% or empty. Read once; it cannot change for a running process.
std::wstring LocalAppData() {
  DWORD size = ::GetEnvironmentVariableW(L"LOCALAPPDATA", nullptr, 0);
  if (size == 0) {
    return std::wstring();
  }
  std::wstring value(size, L'\0');
  const DWORD written =
      ::GetEnvironmentVariableW(L"LOCALAPPDATA", value.data(), size);
  if (written == 0 || written >= size) {
    return std::wstring();
  }
  value.resize(written);
  return value;
}

std::wstring WideFromUtf8(const std::string& text) {
  if (text.empty()) {
    return std::wstring();
  }
  const int needed = ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                                           static_cast<int>(text.size()),
                                           nullptr, 0);
  if (needed <= 0) {
    return std::wstring();
  }
  std::wstring wide(static_cast<size_t>(needed), L'\0');
  ::MultiByteToWideChar(CP_UTF8, 0, text.c_str(),
                        static_cast<int>(text.size()), wide.data(), needed);
  return wide;
}

}  // namespace

std::wstring StartupLogPath() {
  static const std::wstring path = [] {
    const std::wstring base = LocalAppData();
    if (base.empty()) {
      return std::wstring();
    }
    return base + L"\\CCloud\\startup.log";
  }();
  return path;
}

void StartupLog(const std::string& message) {
  const std::wstring path = StartupLogPath();
  if (path.empty()) {
    return;
  }

  const size_t slash = path.find_last_of(L'\\');
  if (slash != std::wstring::npos) {
    ::CreateDirectoryW(path.substr(0, slash).c_str(), nullptr);
  }

  SYSTEMTIME now{};
  ::GetLocalTime(&now);
  char stamp[64];
  std::snprintf(stamp, sizeof(stamp),
                "%04d-%02d-%02d %02d:%02d:%02d.%03d ",
                static_cast<int>(now.wYear), static_cast<int>(now.wMonth),
                static_cast<int>(now.wDay), static_cast<int>(now.wHour),
                static_cast<int>(now.wMinute), static_cast<int>(now.wSecond),
                static_cast<int>(now.wMilliseconds));

  std::lock_guard<std::mutex> lock(g_log_mutex);
  HANDLE file = ::CreateFileW(path.c_str(), FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr,
                              OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
  if (file == INVALID_HANDLE_VALUE) {
    return;
  }
  std::string line(stamp);
  line += message;
  line += "\r\n";
  DWORD written = 0;
  ::WriteFile(file, line.data(), static_cast<DWORD>(line.size()), &written,
              nullptr);
  ::CloseHandle(file);
}

void ShowStartupError(const char* what) {
  const DWORD code = ::GetLastError();
  StartupLog(std::string("ERROR: ") + what +
             " (GetLastError=" + std::to_string(code) + ")");
  g_error_shown.store(true);

  const std::wstring path = StartupLogPath();
  std::wstring message = L"CCloud could not start.\n\n";
  message += WideFromUtf8(what);
  message += L"\n\nWindows error code: " + std::to_wstring(code);
  message += L"\nLog: ";
  message += path.empty() ? std::wstring(L"(startup.log unavailable)")
                          : path;
  message += L"\n\nPlease include the log when reporting this problem.";
  ::MessageBoxW(nullptr, message.c_str(), L"CCloud - startup failed",
                MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
}

bool StartupErrorShown() {
  return g_error_shown.load();
}

void MarkFirstFrame() {
  g_first_frame.store(true);
}

bool HasFirstFrame() {
  return g_first_frame.load();
}

void ShowFirstFrameWarning() {
  const std::wstring path = StartupLogPath();
  StartupLog("ERROR: no first frame within 15 seconds; the window stays hidden");
  std::wstring message =
      L"CCloud started but did not produce its first frame within 15 "
      L"seconds, so the window stays invisible.\n\n"
      L"Try the compatibility build (ZIP named -compat), which turns the "
      L"Impeller renderer off, or read the log:\n";
  message += path.empty() ? std::wstring(L"(startup.log unavailable)") : path;
  message += L"\n\nPlease include the log when reporting this problem.";
  ::MessageBoxW(nullptr, message.c_str(), L"CCloud - window did not appear",
                MB_OK | MB_ICONERROR | MB_SETFOREGROUND);
}
