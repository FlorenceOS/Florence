#include "flo/Containers/StaticVector.hpp"

#include "flo/Algorithm.hpp"
#include "flo/CPU.hpp"
#include "flo/ELF.hpp"
#include "flo/Florence.hpp"
#include "flo/Kernel.hpp"
#include "flo/Memory.hpp"
#include "flo/Paging.hpp"

#include "flo/Containers/Optional.hpp"

#include "Kernel/IO.hpp"

using flo::Decimal;

namespace {
  constexpr bool quiet = false;
  auto pline = flo::makePline<quiet>("[FLORKLOAD]");
}

// Exists in assembly
extern "C" void *stivale_info = nullptr;
extern "C" u64 unknownField;
extern "C" flo::PhysicalFreeList *physFree;
extern "C" flo::VirtualAddress physBase;
extern "C" flo::VirtualAddress physEnd;
extern "C" flo::StaticVector<flo::PhysicalMemoryRange, 0x10ull> *physMemRanges;
extern "C" u32 *vgaX;
extern "C" u32 *vgaY;
extern "C" u8 bundledKernel[];
extern "C" u8 bundledKernelEnd[];

namespace {
  flo::ELF64Image kernelELF{bundledKernel, bundledKernelEnd - bundledKernel};

  auto assertAssumptions = []() {
    auto check =
      [](u64 *value, char const *name) {
        auto v = *value;
        if(unknownField == v) {
          pline("Unset field ", name, "!!");
          flo::CPU::hang();
        }
      };

    check((u64 *)&physFree,      "physFree");
    check((u64 *)&physEnd,       "physEnd");
    check((u64 *)&physMemRanges, "physMemRanges");
    check((u64 *)&vgaX,          "vgaX");
    check((u64 *)&vgaY,          "vgaY");

    Kernel::IO::VGA::currX = *vgaX;
    Kernel::IO::VGA::currY = *vgaY;

    flo::physFree = *physFree;

    pline("Out here");

    for(auto &r: *physMemRanges)
      flo::consumePhysicalMemory(r.begin, r.end() - r.begin());

    flo::Paging::unmap({
      .virt = flo::VirtualAddress{0},
      .size = flo::Util::mega(2ull),
      // Bottom 2M is identity mapped, we don't want to unmap that.
      .recycle_pages = false,
    });

    return flo::nullopt;
  }();

  auto initializeVGA = []() {
    
    return flo::nullopt;
  }();

  auto setPhysFree = []() {
    
    return flo::nullopt;
  }();

  auto consumeLowMemory = []() {
    
    return flo::nullopt;
  }();

  auto unmapLowMemory = []() {
    
    return flo::nullopt;
  }();

}

// Accessible from assembly
extern "C" {
  u64 kernelEntry = 0;
  flo::KernelArguments kernelArguments =
    []() {
      flo::KernelArguments result;
      result.elfImage = &kernelELF;
      result.physFree = &flo::physFree;
      result.physBase = physBase;
      result.physEnd  = physEnd;
      result.type = flo::KernelArguments::BootType::Florence;
      result.flo_boot.vgaX = &Kernel::IO::VGA::currX;
      result.flo_boot.vgaY = &Kernel::IO::VGA::currY;
      return result;
    }();
}

namespace {
  auto loadKernel = []() {
    kernelELF.verify();

    pline("Kernel verified");
    u64 addrHigh = 0;

    kernelELF.forEachProgramHeader([&](flo::ELF64::ProgramHeader const &header) {
      u64 sectionAddrHigh = flo::Paging::align_page_up(header.vaddr() + header.memSz);
      if(sectionAddrHigh > addrHigh)
        addrHigh = sectionAddrHigh;
    });

    addrHigh = flo::Paging::align_page_up<1>(addrHigh);

    kernelELF.loadOffset = (physBase - flo::VirtualAddress{addrHigh})();

    pline("Kernel load offset: ", kernelELF.loadOffset);

    kernelELF.loadAll();

    kernelEntry = kernelELF.header().entry() + kernelELF.loadOffset;

    pline("Kernel entry point: ", kernelEntry);

    return flo::nullopt;
  }();
}

void flo::feedLine() {
  if constexpr(quiet)
    return;

  Kernel::IO::VGA::feedLine();
  Kernel::IO::Debugout::feedLine();
}

void flo::putchar(char c) {
  if constexpr(quiet)
    return;

  if(c == '\n')
    return feedLine();

  Kernel::IO::VGA::putchar(c);
  Kernel::IO::Debugout::write(c);
}

void flo::setColor(flo::TextColor col) {
  if constexpr(quiet)
    return;

  Kernel::IO::VGA::setColor(col);
  Kernel::IO::Debugout::setColor(col);
}

u8 *flo::getPtrPhys(flo::PhysicalAddress phys) {
  return (u8 *)(phys() + physBase());
}

u8 *flo::getPtrVirt(flo::VirtualAddress virt) {
  return (u8 *)virt();
}

void flo::printBacktrace() {
  pline("No stacktrace.");
}
