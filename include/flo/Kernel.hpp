#pragma once

#include "flo/Florence.hpp"
#include "flo/ELF.hpp"

namespace flo {
  struct KernelArguments {
    flo::ELF64Image *elfImage;
    flo::PhysicalAddress physFreeHead1;
    flo::PhysicalAddress physFreeHead2;
    flo::PhysicalAddress physFreeHead3;
    flo::PhysicalAddress physFreeHead4;
    flo::PhysicalAddress physFreeHead5;
    flo::VirtualAddress physBase;
    u64 displayWidth;
    u64 displayHeight;
    u64 displayPitch;
    u64 framebuffer;
    u64 driveNumber;
  };
}
