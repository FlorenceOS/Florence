#include "flo/Containers/StaticVector.hpp"

#include "flo/Algorithm.hpp"
#include "flo/CPU.hpp"
#include "flo/ELF.hpp"
#include "flo/Florence.hpp"
#include "flo/IO.hpp"
#include "flo/Kernel.hpp"
#include "flo/Paging.hpp"

using flo::Decimal;

namespace {
  constexpr bool quiet = false;
  auto pline = flo::makePline<quiet>("[FLORKLOAD]");
}

// Exists in assembly
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
    return flo::nullopt;
  }();

  auto initializeVGA = []() {
    flo::IO::VGA::currX = *vgaX;
    flo::IO::VGA::currY = *vgaY;
    return flo::nullopt;
  }();

  auto setPhysFree = []() {
    flo::physFree = *physFree;
    return flo::nullopt;
  }();

  auto consumeLowMemory = []() {
    for(auto &r: *physMemRanges)
      flo::consumePhysicalMemory(r.begin, r.end() - r.begin());
    return flo::nullopt;
  }();

  auto unmapLowMemory = []() {
    // Don't return the identity mapped pages
    flo::Paging::unmap<false>(flo::VirtualAddress{0}, flo::Util::mega(2ull));
    return flo::nullopt;
  }();

  flo::ELF64Image kernelELF{bundledKernel, bundledKernelEnd - bundledKernel};
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
      result.vgaX = &flo::IO::VGA::currX;
      result.vgaY = &flo::IO::VGA::currY;
      return result;
    }();
}

namespace {
  auto loadKernel = []() {
    auto loadFail = [](auto &&...vs) {
      pline("Error while loading kernel ELF: ", flo::forward<decltype(vs)>(vs)...);
      flo::CPU::halt();
    };

    kernelELF.verify(flo::move(loadFail));

    u64 addrHigh = 0;

    kernelELF.forEachProgramHeader([&](flo::ELF64::ProgramHeader const &header) {
      u64 sectionAddrHigh = flo::Paging::alignPageUp(header.vaddr() + header.memSz);
      if(sectionAddrHigh > addrHigh)
        addrHigh = sectionAddrHigh;
    });

    addrHigh = flo::Paging::alignPageUp<1>(addrHigh);

    kernelELF.loadOffset = (physBase - flo::VirtualAddress{addrHigh})();

    kernelELF.loadAll();

    kernelEntry = kernelELF.header().entry() + kernelELF.loadOffset;
    pline("Entering kernel...");
    return flo::nullopt;
  }();
}

void flo::feedLine() {
  if constexpr(quiet)
    return;

  flo::IO::VGA::feedLine();
  flo::IO::Debugout::feedLine();
}

void flo::putchar(char c) {
  if constexpr(quiet)
    return;

  if(c == '\n')
    return feedLine();

  flo::IO::VGA::putchar(c);
  flo::IO::Debugout::write(c);
}

void flo::setColor(flo::IO::Color col) {
  if constexpr(quiet)
    return;

  flo::IO::VGA::setColor(col);
  flo::IO::Debugout::setColor(col);
}

u8 *flo::getPtrPhys(flo::PhysicalAddress phys) {
  return (u8 *)(phys() + physBase());
}

u8 *flo::getPtrVirt(flo::VirtualAddress virt) {
  return (u8 *)virt();
}
