#include "flo/Containers/StaticVector.hpp"
#include "flo/Algorithm.hpp"
#include "flo/Florence.hpp"
#include "flo/Kernel.hpp"
#include "flo/Paging.hpp"
#include "flo/CPU.hpp"
#include "flo/ELF.hpp"
#include "flo/IO.hpp"

using flo::Decimal;

namespace {
  constexpr bool quiet = false;
  auto pline = flo::makePline<quiet>("[FLORKLOAD] ");
}

// Exists in assembly
extern "C" u64 unknownField;
extern "C" flo::PhysicalFreeList *physFree;
extern "C" flo::VirtualAddress physBase;
extern "C" flo::StaticVector<flo::PhysicalMemoryRange, 0x10ull> *physMemRanges;
extern "C" u64 displayWidth;
extern "C" u64 displayHeight;
extern "C" u64 displayPitch;
extern "C" u64 framebuffer;
extern "C" u64 driveNumber;
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

    check((u64*)&physFree, "physFree");
    check((u64*)&physMemRanges, "physMemRanges");
    check((u64*)&displayWidth, "displayWidth");
    check((u64*)&displayHeight, "displayHeight");
    check((u64*)&displayPitch, "displayPitch");
    check((u64*)&framebuffer, "framebuffer");
    check((u64*)&driveNumber, "driveNumber");
    return flo::nullopt;
  }();

  auto setPhysFree = []() {
    flo::physFree = *physFree;
    return flo::nullopt;
  }();

  auto consumeLowMemory = []() {
    for(auto &r: *physMemRanges) {
      pline("Consuming physical memory [", r.begin(), ", ", r.end(), ")");
      flo::consumePhysicalMemory(r.begin, r.end() - r.begin());
    }
    return flo::nullopt;
  }();

  auto unmapLowMemory = []() {
    // Don't return the identity mapped pages
    flo::Paging::unmap<false>(flo::VirtualAddress{0}, flo::Util::mega(512ull));
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
      result.displayWidth = displayWidth;
      result.displayHeight = displayHeight;
      result.displayPitch = displayPitch;
      result.framebuffer = framebuffer;
      result.driveNumber = driveNumber;
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
    pline("Kernel needs to be offset by ", kernelELF.loadOffset);

    kernelELF.loadAll();

    kernelEntry = kernelELF.header().entry() + kernelELF.loadOffset;
    pline("Entering kernel...");
    return flo::nullopt;
  }();
}

void flo::putchar(char c) {
  if constexpr(!quiet)
    flo::IO::serial1.write(c);
}

void flo::feedLine() {
  if constexpr(!quiet)
    flo::IO::serial1.write('\n');
}

void flo::setColor(flo::IO::Color col) {
  if constexpr(!quiet)
    flo::IO::serial1.setColor(col);
}

u8 *flo::getPtrPhys(flo::PhysicalAddress phys) {
  return (u8 *)(phys() + physBase());
}

u8 *flo::getPtrVirt(flo::VirtualAddress virt) {
  return (u8 *)virt();
}
