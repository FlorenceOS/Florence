#pragma once

#include "flo/Containers/Function.hpp"

namespace flo {
  void yield();
  void exit();

  using threadID = void *;

  // Return some identifier for the currently running thread
  // Not guranteed to be any specific value
  threadID getCurrentThread();

  struct TaskControlBlock {
    bool isRunnable = true; // If false, this task will never be run
    char const *name;
  };

  using TaskFunc = flo::Function<void(TaskControlBlock &)>;
  TaskControlBlock &makeTask(char const *taskName, TaskFunc &&);
}
