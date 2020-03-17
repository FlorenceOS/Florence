#include "flo/Containers/StaticVector.hpp"

#include "flo/Algorithm.hpp"
#include "flo/Bios.hpp"
#include "flo/Bitfields.hpp"
#include "flo/CPU.hpp"
#include "flo/Florence.hpp"
#include "flo/IO.hpp"
#include "flo/Paging.hpp"
#include "flo/Random.hpp"

using flo::Decimal;
using flo::spaces;

// This data needs to be accessible from asm
extern "C" {
  flo::VirtualAddress kernelLoaderEntry;
  flo::VirtualAddress loaderStack;

  u8 diskdata[512];
  flo::BIOS::MemmapEntry mem;
  flo::BIOS::DAP dap;

  u8 driveNumber;
  u8 diskReadCode = 0;

  void readDisk();
}

// Data provided by asm
extern "C" char BootstrapEnd;

auto const minMemory = flo::PhysicalAddress{(u64)&BootstrapEnd};

namespace {
  constexpr bool quiet = false;
  auto pline = flo::makePline<quiet>("[FBTS]");

  // 3 -> aligned to 1GB, 2 -> aligned to 2MB, 1 -> aligned to 4KB etc
  // Every level higher alignment means one factor of 512 less memory overhead
  // but also 9 less bits of entropy.
  // That means lower numbers are more secure but also take more memory.
  constexpr auto kaslrAlignmentLevel = 2;

  // Memory ranges above the 4GB memory limit, we have to wait to
  // consume these to after we've enabled paging.
  flo::StaticVector<flo::PhysicalMemoryRange, 0x10ull> highMemRanges;

  // Base virtual address of physical memory
  flo::VirtualAddress physicalVirtBase;

  // KASLR base for the kernel.
  // The kernel is loaded just below this and physical memory is mapped just above.
  flo::VirtualAddress kaslrBase;

  // Highest memory address spotted
  auto physHigh = minMemory;
}

// IO functions
void flo::feedLine() {
  if constexpr(quiet)
    return;

  flo::IO::VGA::feedLine();
  flo::IO::serial1.feedLine();
}

void flo::putchar(char c) {
  if constexpr(quiet)
    return;

  if(c == '\n')
    return feedLine();

  flo::IO::VGA::putchar(c);
  flo::IO::serial1.write(c);
}

void flo::setColor(flo::IO::Color col) {
  if constexpr(quiet)
    return;

  flo::IO::VGA::setColor(col);
  flo::IO::serial1.setColor(col);
}

namespace {
  flo::VirtualAddress randomizeKASLRBase() {
  redo:
    // We're currently running in 32 bit so we have to generate 32 bits at a time
    auto base = flo::VirtualAddress{flo::getRand()};

    // Align the base
    base = flo::Paging::alignPageDown<kaslrAlignmentLevel>(base);

    // Mask away bits we can't use
    base %= flo::Paging::maxUaddr;

    // Start at possible addresses at 8 GB, we don't wan't to map the lower 4 GB
    if(base < flo::VirtualAddress{flo::Util::giga(8ull)})
      goto redo;

    // End the possible addresses in such a way that we can fit all of our physical memory
    if(base > flo::Paging::maxUaddr + flo::VirtualAddress{physHigh()})
      goto redo;

    // Make the pointer canonical
    base = flo::Paging::makeCanonical(base);

    return base;
  }

  bool shouldUse(flo::BIOS::MemmapEntry const &ent) {
    if(ent.type != flo::BIOS::MemmapEntry::RegionType::Usable)
      return false;

    if(ent.bytesFetched > 20) {
      if(!(ent.attribs & (flo::BIOS::MemmapEntry::ExtendedAttribs::Usable)))
        return false;

      if(ent.attribs & (flo::BIOS::MemmapEntry::ExtendedAttribs::NonVolatile))
        return false;
    }

    return true;
  }

  [[noreturn]]
  void noLong() {
    pline("This doesn't look like a 64 bit CPU, we cannot proceed!");
    flo::CPU::hang();
  }

  void check5Level() {
    u32 ecx;
    asm("cpuid":"=c"(ecx):"a"(7),"c"(0));
    bool supports5lvls = ecx & (1 << 16);

    if constexpr(flo::Paging::PageTableLevels == 4) if(supports5lvls) {
      pline("5 level paging is supported by your CPU");
      pline("Please rebuild florence with 5 level paging support for security reasons");
      pline("You will gain an additional 9 bits of KASLR :)");
    }
    if constexpr(flo::Paging::PageTableLevels == 5) {
      if(!supports5lvls) {
        pline("Florence was built with 5 level paging support, we cannot continue");
        flo::CPU::hang();
      }
      else {
        pline("Enabling 5 level paging...");
        flo::CPU::cr4 |= (1 << 12);
      }
    }
  }

  void checkRDRAND() {
    if(!flo::cpuid.rdrand) {
      pline(flo::IO::Color::red, "Your CPU is missing RDRAND support.");
      pline(flo::IO::Color::red, "Please run Florence with a more modern CPU.");
      pline(flo::IO::Color::red, "If using KVM, use flag \"-cpu host\".");
      pline(flo::IO::Color::red, "We are not able to provide good randomness.");
    }
  }

  void checkLong() {
    u32 eax;
    asm("cpuid":"=a"(eax):"a"(0x80000000));
    if(eax < 0x80000001)
      noLong();
    else {
      u32 edx;
      asm("cpuid":"=d"(edx):"a"(0x80000001));
      if(!(edx & (1 << 29)))
        noLong();
    }
  }

  void assertAssumptions() {
    checkLong();
    check5Level();
    checkRDRAND();
  }

  void fetchMemoryRegion() {
    asm("call getMemoryMap" ::: "eax", "ebx", "ecx", "edx", "di", "memory");
  }

  auto initializeDebug = []() {
    // We always initialize as other bootloader stages could be non-quiet
    flo::IO::serial1.initialize();
    flo::IO::serial2.initialize();
    flo::IO::serial3.initialize();
    flo::IO::serial4.initialize();

    flo::IO::VGA::clear();

    assertAssumptions();
    return flo::nullopt;
  }();
}

void consumeMemory(flo::PhysicalMemoryRange &range) {
  // Make sure we're not taking any memory we're loaded into, we can't
  // use them for our free list as we need to write to them.
  range.begin = flo::max(minMemory, range.begin);

  if(physHigh < range.end)
    physHigh = range.end;

  // First align the memory to whole pages
  range.begin = flo::Paging::alignPageUp(range.begin);
  range.end   = flo::Paging::alignPageDown(range.end);

  // We'll consume the low memory (below 4 GB) before going to 64 bit.
  auto constexpr maxMemory = flo::PhysicalAddress{1} << 32ull;

  auto processLater = [](flo::PhysicalMemoryRange &&mem) {
    pline("Saving ", mem.begin(), " to ", mem.end(), " for later");
    if(highMemRanges.size() < highMemRanges.max_size())
      highMemRanges.emplace_back(flo::move(mem));
  };

  if(range.end > maxMemory) {
    // This chunk ends in 64 bit memory.

    if(range.begin >= maxMemory)
      // It's entirely in 64 bit memory, just save it for later and ignore for now
      return processLater(flo::move(range));

    // It's a little bit of both, split it.
    auto upper = range;
    upper.begin = maxMemory;
    range.end = maxMemory;
    processLater(flo::move(upper));
  }

  pline("Consuming ", range.begin(), " to ", range.end(), " right now");

  // Consume the memory, nom nom
  flo::consumePhysicalMemory(range.begin, range.end() - range.begin());
}

extern "C" void setupMemory() {
  do {
    fetchMemoryRegion();

    if(!mem.bytesFetched)
      break;

    bool use = shouldUse(mem);
    if(use) {
      flo::PhysicalMemoryRange mr;
      mr.begin = mem.base;
      mr.end = mem.base + mem.size;
      consumeMemory(mr);
    }
  } while(mem.savedEbx);
}

extern "C" void doEarlyPaging() {
  // We will locate the physical memory at this point
  kaslrBase = randomizeKASLRBase();
  physicalVirtBase = kaslrBase;

  using PageRoot = flo::Paging::PageTable<flo::Paging::PageTableLevels>;

  // Prepare the paging root
  auto &pageRootPhys = *new((PageRoot *)flo::physFree.getPhysicalPage(1)()) PageRoot();

  // Set the paging root
  flo::CPU::cr3 = (uptr)&pageRootPhys;

  // Align the physical memory size
  physHigh = flo::Paging::alignPageUp<kaslrAlignmentLevel>(physHigh);

  flo::Paging::Permissions permissions;
  permissions.writeEnable = 1;
  permissions.allowUserAccess = 0;
  permissions.writethrough = 0;
  permissions.disableCache = 0;
  permissions.mapping.global = 0;
  permissions.mapping.executeDisable = 1;

  auto err = flo::Paging::map(flo::PhysicalAddress{0}, kaslrBase, physHigh, permissions, pline);

  flo::checkMappingError(err, pline, flo::CPU::hang);

  permissions.mapping.executeDisable = 0;

  // Identity map ourselves to be able to turn on paging
  err = flo::Paging::map(flo::PhysicalAddress{0}, flo::VirtualAddress{0}, flo::Util::mega(2), permissions, pline);
  flo::checkMappingError(err, pline, flo::CPU::hang);
}

namespace {
  void checkReadError() {
    char const *errstr = flo::BIOS::int0x13err(flo::exchange(diskReadCode, 0));
    if(errstr) {
      pline("Disk read error: ", errstr);
      flo::CPU::hang();
    }
  }

  u8 *cppreadDisk(u64 sector) {
    dap.sectorToRead = sector;
    asm("call readDisk":::"eax", "ebx", "ecx", "edx", "edi", "esi", "ebp", "esp", "cc", "memory");
    checkReadError();
    return diskdata;
  }

  void doLoadLoader(u32 startingSector, u32 numPages) {
    auto outAddr = flo::VirtualAddress{flo::Util::giga(1ull)};
    loaderStack = outAddr;

    // RWX, supervisor only
    flo::Paging::Permissions perms;
    perms.writeEnable = 1;
    perms.allowUserAccess = 0;
    perms.writethrough = 0;
    perms.disableCache = 0;
    perms.mapping.executeDisable = 0;

    auto rewriteLoaderHeader =
      [&, passedMagic = false, entryFound = false](u64 *mem) mutable {
        u64 ind = 0;

        if(flo::exchange(passedMagic, true))
          ind += 2;

        while(ind < flo::Paging::PageSize<1>/sizeof(*mem) && !entryFound) {
          switch(mem[ind]) {
          case flo::Util::genMagic("FLORKLOD"):
            // Calculate the virtual address this is loaded at
            kernelLoaderEntry = outAddr + flo::VirtualAddress{(ind + 1) * 8};
            entryFound = true;
            break;

          case flo::Util::genMagic("PhysFree"):
            mem[ind] = (u64)&flo::physFree;
            break;

          case flo::Util::genMagic("PhysBase"):
            mem[ind] = kaslrBase();
            break;

          case flo::Util::genMagic("PhysEnd\x00"):
            mem[ind] = kaslrBase() + physHigh();
            break;

          case flo::Util::genMagic("HighRang"):
            mem[ind] = (u64)&highMemRanges;
            break;

          case flo::Util::genMagic("DispVGAX"):
            mem[ind] = (u64)&flo::IO::VGA::currX;
            break;

          case flo::Util::genMagic("DispVGAY"):
            mem[ind] = (u64)&flo::IO::VGA::currY;
            break;

          default: // Unknown magic
            mem[ind] = flo::Util::genMagic("UNKNOMAG");
            break;
          }
          ++ind;
        }
      };

    for(u32 i = 0; i < numPages; ++i) {
      // Only get 4K pages for now, rewriting the data
      // is kind of hard otherwise without paging.
      auto ppage = flo::physFree.getPhysicalPage(1);

      for(u32 offs = 0; offs < flo::Paging::PageSize<1>; offs += flo::IO::Disk::SectorSize, startingSector += 1) {
        cppreadDisk(startingSector);
        flo::Util::copymem(flo::getPhys<u8>(ppage) + offs, diskdata, flo::IO::Disk::SectorSize);
      }

      auto err = flo::Paging::map(ppage, outAddr, flo::Paging::PageSize<1>, perms, pline);
      flo::checkMappingError(err, pline, flo::CPU::hang);

      rewriteLoaderHeader(flo::getPhys<u64>(ppage));

      outAddr += flo::VirtualAddress{flo::Paging::PageSize<1>};
    }

    if(!kernelLoaderEntry) {
      pline("Could not find kernel loader entry, stopping!");
      flo::CPU::hang();
    }

    perms.writeEnable = 1;
    perms.allowUserAccess = 0;
    perms.writethrough = 0;
    perms.disableCache = 0;
    perms.mapping.executeDisable = 1;

    // Make a stack for the loader
    auto constexpr loaderStackSize = flo::Util::kilo(4);
    auto err = flo::Paging::map(loaderStack - flo::VirtualAddress{loaderStackSize}, loaderStackSize, perms);
    flo::checkMappingError(err, pline, flo::CPU::hang);
  }
}

extern "C" void loadKernelLoader() {
  u8 const magic[16] {
    0x09, 0xF9, 0x11, 0x02, 0x9D, 0x74, 0xE3, 0x5B,
    0xD8, 0x41, 0x56, 0xC5, 0x63, 0x56, 0x88, 0xC0,
  };

  for(u32 loaderSector = 0; loaderSector < 1000; ++loaderSector) {
    cppreadDisk(loaderSector);

    if(flo::Util::memeq(magic, diskdata, sizeof(magic))) {
      u32 loaderPages = flo::Util::get<u32>(diskdata, sizeof(magic));

      doLoadLoader(loaderSector, loaderPages);
      return;
    }
  }
  pline("Kernel loader not found in first 1000 sectors of disk. Giving up.");
  flo::CPU::hang();
}

u8 *flo::getPtrPhys(flo::PhysicalAddress addr) {
  return (u8 *)addr();
}

/*
Function not implemented, prefer linker error
template<>
u8 *flo::getPtrVirt<sizeof(uptr)>(flo::VirtualAddress addr) {

}
*/
