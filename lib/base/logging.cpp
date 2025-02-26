/*
 * Copyright (C) 2015 The Android Open Source Project
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#if defined(_WIN32)
#include <windows.h>
#endif

#include "android-base/logging.h"

#include <fcntl.h>
#include <libgen.h>
#include <time.h>

// For getprogname(3) or program_invocation_short_name.
#if defined(__ANDROID__) || defined(__APPLE__)
#include <stdlib.h>
#elif defined(__GLIBC__)
#include <errno.h>
#endif

#if defined(__linux__)
#include <sys/uio.h>
#endif

#include <iostream>
#include <limits>
#include <mutex>
#include <sstream>
#include <string.h>
#include <utility>
#include <vector>

// Headers for LogMessage::LogLine.
#ifdef __ANDROID__
#include <log/log.h>
//#include <android/set_abort_message.h>
#else
#include <sys/types.h>
#include <unistd.h>
#endif

#include <android-base/macros.h>
#include <android-base/strings.h>

// For gettid.
#if defined(__APPLE__)
#include "AvailabilityMacros.h"  // For MAC_OS_X_VERSION_MAX_ALLOWED
#include <stdint.h>
#include <stdlib.h>
#include <sys/syscall.h>
#include <sys/time.h>
#include <unistd.h>
#elif defined(__linux__) && !defined(__ANDROID__)
#include <syscall.h>
#include <unistd.h>
#elif defined(_WIN32)
#include <windows.h>
#endif

#if defined(_WIN32)
typedef uint32_t thread_id;
#else
typedef pid_t thread_id;
#endif

static thread_id GetThreadId() {
#if defined(__BIONIC__)
  return gettid();
#elif defined(__APPLE__)
  return syscall(SYS_thread_selfid);
#elif defined(__linux__)
  return syscall(__NR_gettid);
#elif defined(_WIN32)
  return GetCurrentThreadId();
#endif
}

namespace {
#if defined(__GLIBC__)
const char* getprogname() {
  return program_invocation_short_name;
}
#elif defined(_WIN32)
const char* getprogname() {
  static bool first = true;
  static char progname[MAX_PATH] = {};

  if (first) {
    CHAR longname[MAX_PATH];
    DWORD nchars = GetModuleFileNameA(nullptr, longname, arraysize(longname));
    if ((nchars >= arraysize(longname)) || (nchars == 0)) {
      // String truncation or some other error.
      strcpy(progname, "<unknown>");
    } else {
      strcpy(progname, basename(longname));
    }
    first = false;
  }

  return progname;
}
#endif
} // namespace

namespace android {
namespace base {

static std::mutex& LoggingLock() {
  static auto& logging_lock = *new std::mutex();
  return logging_lock;
}

static LogFunction& Logger() {
#ifdef __ANDROID__
  static auto& logger = *new LogFunction(LogdLogger());
#else
  static auto& logger = *new LogFunction(StderrLogger);
#endif
  return logger;
}

static AbortFunction& Aborter() {
  static auto& aborter = *new AbortFunction(DefaultAborter);
  return aborter;
}

static std::string& ProgramInvocationName() {
  static auto& programInvocationName = *new std::string(getprogname());
  return programInvocationName;
}

static bool gInitialized = false;
static LogSeverity gMinimumLogSeverity = INFO;

#if defined(__linux__)
void KernelLogger(android::base::LogId, android::base::LogSeverity severity,
                  const char* tag, const char*, unsigned int, const char* msg) {
  // clang-format off
  static constexpr int kLogSeverityToKernelLogLevel[] = {
      [android::base::VERBOSE] = 7,              // KERN_DEBUG (there is no verbose kernel log
                                                 //             level)
      [android::base::DEBUG] = 7,                // KERN_DEBUG
      [android::base::INFO] = 6,                 // KERN_INFO
      [android::base::WARNING] = 4,              // KERN_WARNING
      [android::base::ERROR] = 3,                // KERN_ERROR
      [android::base::FATAL_WITHOUT_ABORT] = 2,  // KERN_CRIT
      [android::base::FATAL] = 2,                // KERN_CRIT
  };
  // clang-format on
  static_assert(arraysize(kLogSeverityToKernelLogLevel) == android::base::FATAL + 1,
                "Mismatch in size of kLogSeverityToKernelLogLevel and values in LogSeverity");

  static int klog_fd = TEMP_FAILURE_RETRY(open("/dev/kmsg", O_WRONLY | O_CLOEXEC));
  if (klog_fd == -1) return;

  int level = kLogSeverityToKernelLogLevel[severity];

  // The kernel's printk buffer is only 1024 bytes.
  // TODO: should we automatically break up long lines into multiple lines?
  // Or we could log but with something like "..." at the end?
  char buf[1024];
  size_t size = snprintf(buf, sizeof(buf), "<%d>%s: %s\n", level, tag, msg);
  if (size > sizeof(buf)) {
    size = snprintf(buf, sizeof(buf), "<%d>%s: %zu-byte message too long for printk\n",
                    level, tag, size);
  }

  iovec iov[1];
  iov[0].iov_base = buf;
  iov[0].iov_len = size;
  TEMP_FAILURE_RETRY(writev(klog_fd, iov, 1));
}
#endif

void StderrLogger(LogId, LogSeverity severity, const char*, const char* file,
                  unsigned int line, const char* message) {
  struct tm now;
  time_t t = time(nullptr);

#if defined(_WIN32)
  localtime_s(&now, &t);
#else
  localtime_r(&t, &now);
#endif

  char timestamp[32];
  strftime(timestamp, sizeof(timestamp), "%m-%d %H:%M:%S", &now);

  static const char log_characters[] = "VDIWEFF";
  static_assert(arraysize(log_characters) - 1 == FATAL + 1,
                "Mismatch in size of log_characters and values in LogSeverity");
  char severity_char = log_characters[severity];
  fprintf(stderr, "%s %c %s %5d %5d %s:%u] %s\n", ProgramInvocationName().c_str(),
          severity_char, timestamp, getpid(), GetThreadId(), file, line, message);
}

void DefaultAborter(const char* abort_message) {
#ifdef __ANDROID__
  //android_set_abort_message(abort_message);
#else
  UNUSED(abort_message);
#endif
  abort();
}


#ifdef __ANDROID__
LogdLogger::LogdLogger(LogId default_log_id) : default_log_id_(default_log_id) {
}

void LogdLogger::operator()(LogId id, LogSeverity severity, const char* tag,
                            const char* file, unsigned int line,
                            const char* message) {
  static constexpr android_LogPriority kLogSeverityToAndroidLogPriority[] = {
      ANDROID_LOG_VERBOSE, ANDROID_LOG_DEBUG, ANDROID_LOG_INFO,
      ANDROID_LOG_WARN,    ANDROID_LOG_ERROR, ANDROID_LOG_FATAL,
      ANDROID_LOG_FATAL,
  };
  static_assert(arraysize(kLogSeverityToAndroidLogPriority) == FATAL + 1,
                "Mismatch in size of kLogSeverityToAndroidLogPriority and values in LogSeverity");

  int priority = kLogSeverityToAndroidLogPriority[severity];
  if (id == DEFAULT) {
    id = default_log_id_;
  }

  static constexpr log_id kLogIdToAndroidLogId[] = {
    LOG_ID_MAX, LOG_ID_MAIN, LOG_ID_SYSTEM,
  };
  static_assert(arraysize(kLogIdToAndroidLogId) == SYSTEM + 1,
                "Mismatch in size of kLogIdToAndroidLogId and values in LogId");
  //log_id lg_id = kLogIdToAndroidLogId[id];

  if (priority == ANDROID_LOG_FATAL) {
    //__android_log_buf_print(lg_id, priority, tag, "%s:%u] %s", file, line,
                           // message);
  } else {
    //__android_log_buf_print(lg_id, priority, tag, "%s", message);
  }
}
#endif

void InitLogging(char* argv[], LogFunction&& logger, AbortFunction&& aborter) {
  SetLogger(std::forward<LogFunction>(logger));
  SetAborter(std::forward<AbortFunction>(aborter));

  if (gInitialized) {
    return;
  }

  gInitialized = true;

  // Stash the command line for later use. We can use /proc/self/cmdline on
  // Linux to recover this, but we don't have that luxury on the Mac/Windows,
  // and there are a couple of argv[0] variants that are commonly used.
  if (argv != nullptr) {
    std::lock_guard<std::mutex> lock(LoggingLock());
    ProgramInvocationName() = basename(argv[0]);
  }

  const char* tags = getenv("ANDROID_LOG_TAGS");
  if (tags == nullptr) {
    return;
  }

  std::vector<std::string> specs = Split(tags, " ");
  for (size_t i = 0; i < specs.size(); ++i) {
    // "tag-pattern:[vdiwefs]"
    std::string spec(specs[i]);
    if (spec.size() == 3 && StartsWith(spec, "*:")) {
      switch (spec[2]) {
        case 'v':
          gMinimumLogSeverity = VERBOSE;
          continue;
        case 'd':
          gMinimumLogSeverity = DEBUG;
          continue;
        case 'i':
          gMinimumLogSeverity = INFO;
          continue;
        case 'w':
          gMinimumLogSeverity = WARNING;
          continue;
        case 'e':
          gMinimumLogSeverity = ERROR;
          continue;
        case 'f':
          gMinimumLogSeverity = FATAL_WITHOUT_ABORT;
          continue;
        // liblog will even suppress FATAL if you say 's' for silent, but that's
        // crazy!
        case 's':
          gMinimumLogSeverity = FATAL_WITHOUT_ABORT;
          continue;
      }
    }
    LOG(FATAL) << "unsupported '" << spec << "' in ANDROID_LOG_TAGS (" << tags
               << ")";
  }
}

void SetLogger(LogFunction&& logger) {
  std::lock_guard<std::mutex> lock(LoggingLock());
  Logger() = std::move(logger);
}

void SetAborter(AbortFunction&& aborter) {
  std::lock_guard<std::mutex> lock(LoggingLock());
  Aborter() = std::move(aborter);
}

static const char* GetFileBasename(const char* file) {
  // We can't use basename(3) even on Unix because the Mac doesn't
  // have a non-modifying basename.
  const char* last_slash = strrchr(file, '/');
  if (last_slash != nullptr) {
    return last_slash + 1;
  }
#if defined(_WIN32)
  const char* last_backslash = strrchr(file, '\\');
  if (last_backslash != nullptr) {
    return last_backslash + 1;
  }
#endif
  return file;
}

// This indirection greatly reduces the stack impact of having lots of
// checks/logging in a function.
class LogMessageData {
 public:
  LogMessageData(const char* file, unsigned int line, LogId id,
                 LogSeverity severity, int error)
      : file_(GetFileBasename(file)),
        line_number_(line),
        id_(id),
        severity_(severity),
        error_(error) {
  }

  const char* GetFile() const {
    return file_;
  }

  unsigned int GetLineNumber() const {
    return line_number_;
  }

  LogSeverity GetSeverity() const {
    return severity_;
  }

  LogId GetId() const {
    return id_;
  }

  int GetError() const {
    return error_;
  }

  std::ostream& GetBuffer() {
    return buffer_;
  }

  std::string ToString() const {
    return buffer_.str();
  }

 private:
  std::ostringstream buffer_;
  const char* const file_;
  const unsigned int line_number_;
  const LogId id_;
  const LogSeverity severity_;
  const int error_;

  DISALLOW_COPY_AND_ASSIGN(LogMessageData);
};

LogMessage::LogMessage(const char* file, unsigned int line, LogId id,
                       LogSeverity severity, int error)
    : data_(new LogMessageData(file, line, id, severity, error)) {
}

LogMessage::~LogMessage() {
  // Check severity again. This is duplicate work wrt/ LOG macros, but not LOG_STREAM.
  if (!WOULD_LOG(data_->GetSeverity())) {
    return;
  }

  // Finish constructing the message.
  if (data_->GetError() != -1) {
    data_->GetBuffer() << ": " << strerror(data_->GetError());
  }
  std::string msg(data_->ToString());

  {
    // Do the actual logging with the lock held.
    std::lock_guard<std::mutex> lock(LoggingLock());
    if (msg.find('\n') == std::string::npos) {
      LogLine(data_->GetFile(), data_->GetLineNumber(), data_->GetId(),
              data_->GetSeverity(), msg.c_str());
    } else {
      msg += '\n';
      size_t i = 0;
      while (i < msg.size()) {
        size_t nl = msg.find('\n', i);
        msg[nl] = '\0';
        LogLine(data_->GetFile(), data_->GetLineNumber(), data_->GetId(),
                data_->GetSeverity(), &msg[i]);
        // Undo the zero-termination so we can give the complete message to the aborter.
        msg[nl] = '\n';
        i = nl + 1;
      }
    }
  }

  // Abort if necessary.
  if (data_->GetSeverity() == FATAL) {
    Aborter()(msg.c_str());
  }
}

std::ostream& LogMessage::stream() {
  return data_->GetBuffer();
}

void LogMessage::LogLine(const char* file, unsigned int line, LogId id,
                         LogSeverity severity, const char* message) {
  const char* tag = ProgramInvocationName().c_str();
  Logger()(id, severity, tag, file, line, message);
}

LogSeverity GetMinimumLogSeverity() {
    return gMinimumLogSeverity;
}

LogSeverity SetMinimumLogSeverity(LogSeverity new_severity) {
  LogSeverity old_severity = gMinimumLogSeverity;
  gMinimumLogSeverity = new_severity;
  return old_severity;
}

ScopedLogSeverity::ScopedLogSeverity(LogSeverity new_severity) {
  old_ = SetMinimumLogSeverity(new_severity);
}

ScopedLogSeverity::~ScopedLogSeverity() {
  SetMinimumLogSeverity(old_);
}

}  // namespace base
}  // namespace android
