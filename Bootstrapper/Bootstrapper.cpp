#include "flo/Containers/StaticVector.hpp"

#include "flo/Algorithm.hpp"
#include "flo/Bios.hpp"
#include "flo/Bitfields.hpp"
#include "flo/CPU.hpp"
#include "flo/Florence.hpp"
#include "flo/Kernel.hpp"
#include "flo/Memory.hpp"
#include "flo/Paging.hpp"
#include "flo/Random.hpp"

#include "flo/Containers/Optional.hpp"

#include "Kernel/IO.hpp"

// This data needs to be accessible from asm
extern "C" {
  flo::VirtualAddress kernelLoaderEntry = flo::VirtualAddress{0};
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

namespace {
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

  bool shouldMap(flo::BIOS::MemmapEntry const &ent) {
    switch(ent.type) {
    case flo::BIOS::MemmapEntry::RegionType::Usable: return true;
    case flo::BIOS::MemmapEntry::RegionType::Reserved: return true;
    case flo::BIOS::MemmapEntry::RegionType::ACPIReclaimable: return true;
    case flo::BIOS::MemmapEntry::RegionType::ACPINonReclaimable: return true;
    case flo::BIOS::MemmapEntry::RegionType::Bad: return false;
    default: assert_not_reached();
    }
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
      pline(flo::TextColor::red, "Your CPU is missing RDRAND support.");
      pline(flo::TextColor::red, "Please run Florence with a more modern CPU.");
      pline(flo::TextColor::red, "If using KVM, use flag \"-cpu host\".");
      pline(flo::TextColor::red, "We are not able to provide good randomness.");
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
    Kernel::IO::serial1.initialize();
    Kernel::IO::serial2.initialize();
    Kernel::IO::serial3.initialize();
    Kernel::IO::serial4.initialize();

    Kernel::IO::VGA::clear();

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
  range.begin = flo::Paging::align_page_up(range.begin);
  range.end   = flo::Paging::align_page_down(range.end);

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

    //pline("Base: ", mem.base, " size: ", mem.size, " type: ", (u32)mem.type);

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
  // Align the physical memory size
  physHigh = flo::Paging::align_page_up<flo::kaslr_alignment_level>(physHigh);

  // We will locate the physical memory at this point
  kaslrBase = flo::bootstrap_aslr_base(physHigh);
  physicalVirtBase = kaslrBase;

  // Prepare the paging root
  //auto pageRoot = flo::physFree.getPhysicalPage(1);

  auto pageRoot = flo::Paging::make_paging_root();

  // Set the paging root
  flo::Paging::set_root(pageRoot);

  // Identity map ourselves
  flo::Paging::Permissions permissions;
  permissions.readable = 1;
  permissions.writeable = 1;
  permissions.userspace = 0;
  permissions.writethrough = 1;
  permissions.cacheable = 1;
  permissions.global = 0;
  permissions.executable = 1;

  flo::Paging::map_phys({
    .phys = flo::PhysicalAddress{0},
    .virt = flo::VirtualAddress{0},
    .size = flo::Util::mega(2),
    .perm = permissions,
  });

  // Map physical memory
  permissions.executable = 0;

  mem.savedEbx = 0;
  do {
    fetchMemoryRegion();

    if(!mem.bytesFetched)
      break;
    
    mem.base = [&]() {
      auto base = flo::Paging::align_page_up(mem.base);
      mem.size = flo::Paging::align_page_down(mem.size - (base - mem.base));
      return base;
    }();

    if(mem.base() >= 0x100000 && shouldMap(mem))
      flo::Paging::map_phys({
        .phys = mem.base,
        .virt = kaslrBase + flo::VirtualAddress{mem.base()},
        .size = mem.size,
        .perm = permissions,
      });
  } while(mem.savedEbx);

  // Map low memory
  flo::Paging::map_phys({
    .phys = flo::PhysicalAddress{0},
    .virt = kaslrBase,
    .size = 0x100000,
    .perm = permissions,
  });
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
    perms.readable = 1;
    perms.writeable = 1;
    perms.userspace = 0;
    perms.writethrough = 0;
    perms.cacheable = 1;
    perms.executable = 1;

    auto rewriteLoaderHeader =
      [&, passedMagic = false](u64 *mem) mutable {
        u64 ind = 0;

        if(flo::exchange(passedMagic, true))
          ind += 2;

        while(ind < flo::Paging::PageSize<1>/sizeof(*mem) && !kernelLoaderEntry) {
          switch(mem[ind]) {
          case flo::Util::genMagic("FLORKLOD"):
            // Calculate the virtual address this is loaded at
            kernelLoaderEntry = outAddr + flo::VirtualAddress{(ind + 1) * 8};
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
            mem[ind] = (u64)&Kernel::IO::VGA::currX;
            break;

          case flo::Util::genMagic("DispVGAY"):
            mem[ind] = (u64)&Kernel::IO::VGA::currY;
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

      flo::Paging::map_phys({
        .phys = ppage,
        .virt = outAddr,
        .size = flo::Paging::PageSize<1>,
        .perm = perms,
      });

      rewriteLoaderHeader(flo::getPhys<u64>(ppage));

      outAddr += flo::VirtualAddress{flo::Paging::PageSize<1>};
    }

    if(!kernelLoaderEntry) {
      pline("Could not find kernel loader entry, stopping!");
      flo::CPU::hang();
    }

    perms.readable = 1;
    perms.writeable = 1;
    perms.userspace = 0;
    perms.writethrough = 0;
    perms.cacheable = 1;
    perms.executable = 0;

    // Make a stack for the loader
    auto constexpr loaderStackSize = flo::Util::kilo(32);
    flo::Paging::map({
      .virt = loaderStack - flo::VirtualAddress{loaderStackSize},
      .size = loaderStackSize,
      .perm = perms,
    });
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
