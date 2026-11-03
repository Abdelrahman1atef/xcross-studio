#ifndef RUNNER_CHILD_PROCESSES_H_
#define RUNNER_CHILD_PROCESSES_H_

#include <string>

// Puts this process in a Windows job that ends every process it starts (xcross
// and the tools xcross runs) when this process ends, however it ends: closing
// the window, a crash or Task Manager. Without it a `devices --watch` outlived
// the window and kept the app's CLI files locked. Call once, before any child
// starts.
void EndChildProcessesWithApp();

// Opens a folder, file or URL with Explorer started outside that job, so the
// window or browser it opens stays open after the app closes. Takes UTF-8.
bool OpenOutsideApp(const std::string& target);

#endif  // RUNNER_CHILD_PROCESSES_H_
