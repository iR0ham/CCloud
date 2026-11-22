#ifndef RUNNER_STARTUP_LOG_H_
#define RUNNER_STARTUP_LOG_H_

#include <string>

// Startup diagnostics for the Windows runner.
//
// The Flutter runner used to fail without any trace: a failed window creation
// or a renderer that never presented a frame left a process alive with no
// window and no message. Everything logged here goes to
// %LOCALAPPDATA%\CCloud\startup.log; when that location is unavailable
// logging silently does nothing (nothing is ever written elsewhere).

// Full path of the startup log, or an empty string when LOCALAPPDATA is not
// available. The path itself never depends on the working directory.
std::wstring StartupLogPath();

// Appends one timestamped UTF-8 line. Thread-safe, never throws, and never
// blocks startup on a failed write.
void StartupLog(const std::string& message);

// Logs |what| together with the current GetLastError() and shows a blocking
// error box naming the log path. Meant for unrecoverable startup failures.
void ShowStartupError(const char* what);

// Whether an error box was already shown, so the top-level failure path does
// not stack a second identical dialog on top of it.
bool StartupErrorShown();

// First-frame bookkeeping shared by the window and the watchdog.
void MarkFirstFrame();
bool HasFirstFrame();

// Explains a missing first frame and points at the log and the compat build.
void ShowFirstFrameWarning();

#endif  // RUNNER_STARTUP_LOG_H_
