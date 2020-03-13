#pragma once

#include "Ints.hpp"

namespace flo {
  struct ThreadState;

  // Exits the process. You may finally rest.
  [[noreturn]]
  void exit();

  // Tells the kernel that hey, you're pretty cool.
  void ping();

  // Report that you are in an invalid/unhandled state.
  // The process will be killed.
  [[noreturn]]
  void crash(char const *filename, u64 line, char const *errorMessage);

  // Report that something went wrong.
  // You will continue on with your struggles, no rest for the wicked.
  void warn(char const *filename, u64 line, char const *errorMessage);

  // Exits the current thread
  [[noreturn]]
  void exitThread();

  // Creates a new thread
  void spawnThread(ThreadState *);
}
