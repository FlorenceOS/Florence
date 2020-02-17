#pragma once

#include "flo/Florence.hpp"
#include "flo/ELF.hpp"

namespace flo {
  struct KernelArguments {
    flo::ELF64Image *elfImage;
    flo::PhysicalFreeList *physFree;
    flo::VirtualAddress physBase;
    u64 displayWidth;
    u64 displayHeight;
    u64 displayPitch;
    u64 framebuffer;
    u64 driveNumber;
  };
}
