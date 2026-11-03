#include "child_processes.h"

#include <windows.h>

#include <vector>

void EndChildProcessesWithApp() {
  HANDLE job = ::CreateJobObjectW(nullptr, nullptr);
  if (job == nullptr) {
    return;
  }
  JOBOBJECT_EXTENDED_LIMIT_INFORMATION info = {};
  // Breakaway stays allowed for OpenOutsideApp.
  info.BasicLimitInformation.LimitFlags =
      JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE | JOB_OBJECT_LIMIT_BREAKAWAY_OK;
  if (!::SetInformationJobObject(job, JobObjectExtendedLimitInformation, &info,
                                 sizeof(info)) ||
      !::AssignProcessToJobObject(job, ::GetCurrentProcess())) {
    ::CloseHandle(job);
    return;
  }
  // The handle is left open on purpose: Windows closes it when this process
  // ends, and closing the last handle ends the job's processes.
}

static std::wstring Utf16FromUtf8(const std::string& utf8) {
  if (utf8.empty()) {
    return std::wstring();
  }
  int length = ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                                     static_cast<int>(utf8.size()), nullptr, 0);
  if (length <= 0) {
    return std::wstring();
  }
  std::wstring utf16(length, L'\0');
  ::MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, utf8.data(),
                        static_cast<int>(utf8.size()), utf16.data(), length);
  return utf16;
}

bool OpenOutsideApp(const std::string& target) {
  std::wstring wide_target = Utf16FromUtf8(target);
  if (wide_target.empty() || wide_target.find(L'"') != std::wstring::npos) {
    return false;
  }
  wchar_t windows[MAX_PATH];
  UINT length = ::GetWindowsDirectoryW(windows, MAX_PATH);
  if (length == 0 || length >= MAX_PATH) {
    return false;
  }
  std::wstring explorer = std::wstring(windows) + L"\\explorer.exe";
  std::wstring command = L"\"" + explorer + L"\" \"" + wide_target + L"\"";
  std::vector<wchar_t> command_line(command.begin(), command.end());
  command_line.push_back(L'\0');

  for (DWORD flags : {static_cast<DWORD>(CREATE_BREAKAWAY_FROM_JOB),
                      static_cast<DWORD>(0)}) {
    STARTUPINFOW startup = {};
    startup.cb = sizeof(startup);
    PROCESS_INFORMATION process = {};
    // Without breakaway when an outer job does not allow it.
    if (::CreateProcessW(explorer.c_str(), command_line.data(), nullptr,
                         nullptr, FALSE, flags, nullptr, nullptr, &startup,
                         &process)) {
      ::CloseHandle(process.hThread);
      ::CloseHandle(process.hProcess);
      return true;
    }
  }
  return false;
}
