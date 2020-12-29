#pragma once

#include "flo/ELF.hpp"
#include "flo/Florence.hpp"

namespace flo {
  struct KernelArguments {
    flo::ELF64Image const *elfImage;
    flo::PhysicalFreeList const *physFree;
    flo::VirtualAddress physBase;
    flo::VirtualAddress physEnd;

    enum struct BootType {
      Florence,
      Stivale,
      Multiboot,
    };

    BootType type;

    union {
      struct {
        flo::PhysicalAddress rsdp;
        flo::PhysicalAddress fb;
        u16 pitch;
        u16 width;
        u16 height;
        u16 bpp;
      } stivale_boot;

      struct {
        u32 const *vgaX;
        u32 const *vgaY;
      } flo_boot;
    };
  };

  void printBacktrace();
  void printBacktrace(uptr basePointer);
  uptr deslide(uptr addr);
  char const *symbolName(uptr addr);

  // 3 -> aligned to 1GB, 2 -> aligned to 2MB, 1 -> aligned to 4KB etc
  // Every level higher alignment means one factor of 512 less memory overhead
  // but also 9 less bits of entropy.
  // That means lower numbers are more secure but also take more memory.
  constexpr auto kaslr_alignment_level = 3;

  flo::VirtualAddress bootstrap_aslr_base(u64 highest_phys_addr);
}

extern "C" void *makeStack();
extern "C" void freeStack(void *stack);
