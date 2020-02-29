#pragma once

#include "flo/ELF.hpp"
#include "flo/Florence.hpp"

namespace flo {
  struct KernelArguments {
    flo::ELF64Image *elfImage;
    flo::PhysicalFreeList *physFree;
    flo::VirtualAddress physBase;
    u64 displayWidth;
    u64 displayHeight;
    u64 displayPitch;
    flo::PhysicalAddress framebuffer;
    u64 driveNumber;
  };

  void printBacktrace();
}
