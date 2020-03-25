#pragma once

#include "flo/Containers/Function.hpp"
#include "flo/ELF.hpp"
#include "flo/Florence.hpp"

namespace flo {
  struct KernelArguments {
    flo::ELF64Image const *elfImage;
    flo::PhysicalFreeList const *physFree;
    flo::VirtualAddress physBase;
    flo::VirtualAddress physEnd;
    u32 const *vgaX;
    u32 const *vgaY;
  };

  void printBacktrace();
  uptr deslide(uptr addr);
  char const *symbolName(uptr addr);
  void yield();
  void exit();

  struct TaskControlBlock {
    bool isRunnable = true; // If false, this task will never be run
    char const *name;
  };

  TaskControlBlock &makeTask(char const *taskName, flo::Function<void(TaskControlBlock &)> &&);
}

extern "C" void *makeStack();
extern "C" void freeStack(void *stack);
