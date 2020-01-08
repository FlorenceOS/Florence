#include "flo/IO.hpp"
#include "flo/CPU.hpp"
#include "flo/Bios.hpp"
#include "flo/Paging.hpp"
#include "flo/Random.hpp"
#include "flo/Florence.hpp"
#include "flo/Bitfields.hpp"

#include "flo/Containers/StaticVector.hpp"

#include <algorithm>

using Constructor = void(*)();

extern "C" Constructor constructorsStart;
extern "C" Constructor constructorsEnd;

extern "C" void doConstructors() {
  std::for_each(&constructorsStart, &constructorsEnd, [](Constructor c){
    (*c)();
  });
}

using flo::Decimal;
using flo::spaces;

namespace {
  constexpr bool quiet = false;
  constexpr bool disableKASLR = true;
  bool vgaDisabled = false;

  struct MemoryRange {
    flo::PhysicalAddress begin;
    flo::PhysicalAddress end;
  };

  // Memory ranges above the 4GB memory limit, we have to wait to
  // consume these to after we've enabled paging.
  flo::StaticVector<MemoryRange, 0x10> highMemRanges;

  // Head of physical page freelist
  flo::PhysicalAddress physicalFreeList = flo::PhysicalAddress{0};

  // Base virtual address of physical memory
  flo::VirtualAddress physicalVirtBase;

  auto pline = flo::makePline("[FBTS] ");

  // KASLR base for the kernel.
  // The kernel is loaded just below this and physical memory is mapped just above.
  flo::VirtualAddress kaslrBase;

  // Info about the display we've ended up picking goes in here
  struct {
    u64 framebuffer;
    u32 width;
    u32 height;
    u32 bpp;
    u32 pitch;
    u16 mode; 
  } pickedDisplay;
};

// This data needs to be accessible from asm
extern "C" {
  flo::VirtualAddress kernelLoaderEntry;
  flo::VirtualAddress loaderStack;
}

// Data provided by asm
extern "C" u16 desiredWidth;
extern "C" u16 desiredHeight;
extern "C" u8 diskNum;
extern "C" union { struct flo::BIOS::VesaInfo vesa; struct flo::BIOS::MemmapEntry mem; } biosBuf;
extern "C" union { struct flo::BIOS::DAP dap; struct flo::BIOS::VideoMode vm; } currentModeBuf;
extern "C" char BootstrapEnd;

// Typed references to the data provided just above
auto &vesa = biosBuf.vesa;
auto &mem  = biosBuf.mem;
auto diskdata = (u8 *)&biosBuf;
auto &vidmode = currentModeBuf.vm;
auto &dap = currentModeBuf.dap;
auto const minMemory = flo::PhysicalAddress{(u64)&BootstrapEnd};

// IO functions
void flo::feedLine() {
  if constexpr(quiet)
    return;

  if(!vgaDisabled)
    flo::IO::VGA::feedLine();
  flo::IO::serial1.feedLine();
}

void flo::putchar(char c) {
  if constexpr(quiet)
    return;

  if(c == '\n')
    return feedLine();

  if(!vgaDisabled)
    flo::IO::VGA::putchar(c);
  flo::IO::serial1.write(c);
}

void flo::setColor(flo::IO::Color col) {
  if constexpr(quiet)
    return;

  if(!vgaDisabled)
    flo::IO::VGA::setColor(col);
  flo::IO::serial1.setColor(col);
}

namespace {
  bool shouldUse(flo::BIOS::MemmapEntry const &ent) {
    if(ent.type != flo::BIOS::MemmapEntry::RegionType::Usable)
      return false;

    if(ent.bytesFetched > 20)
      if(ent.attribs & (flo::BIOS::MemmapEntry::ExtendedAttribs::Ignore | flo::BIOS::MemmapEntry::ExtendedAttribs::NonVolatile))
        return false;

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

    pline("5 level paging is ", supports5lvls ? "" : "not", " supported by your CPU");
    if constexpr(flo::Paging::PageTableLevels == 4) if(supports5lvls) {
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
        flo::CPU::cr4 = flo::CPU::cr4 | (1 << 12);
      }
    }
  }

  void checkRDRAND() {
    if constexpr(!disableKASLR) {
      u32 ecx;
      asm("cpuid" : "=c"(ecx) : "a"(1));
      if(!(ecx & (1 << 30))) {
        pline("ERROR: Your CPU is missing RDRAND support."),
        pline("Please run Florence with a more modern CPU.");
        pline("If using KVM, use flag \"-cpu host\".");
        pline("If you don't have RDRAND, disable KASLR.");

        flo::CPU::hang();
      }
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

  template<typename PT>
  void printPaging(PT &pt, u64 virtaddr = 0, u8 indent = 0) {
    bool visitedAny = false;
    for(int i = 0; i < flo::Paging::PageTableSize; ++ i) {
      auto &ent = pt.table[i];
      [[maybe_unused]]
      auto nextVirt = flo::Paging::makeCanonical(virtaddr | ((u64)i << flo::Paging::pageOffsetBits<ent.lvl>));
      if(!ent.present)
        continue;

      visitedAny = true;
      
      if constexpr(flo::Paging::noisy)
        pline(spaces(indent), "Entry ", Decimal{i}, " at ", (u32)&ent," (", nextVirt, ", ", ent.rep, ") mapping to ", ent.isMapping() ? "physical addr " : "page table at physical ", ent.physaddr()());
      if(!ent.isMapping()) {
        if constexpr(ent.lvl < 2) {
          pline(spaces(indent + 1), "Present level 1 mapping without mapping bit set!!");
          continue;
        }
        else {
          pline(spaces(indent), "Entry ", Decimal{i}, " at ", (u32)&ent," (", nextVirt, ", ", ent.rep, ") mapping to page table at physical ", ent.physaddr()());
          auto ptr = flo::getPhys<flo::Paging::PageTable<ent.lvl - 1>>(ent.physaddr());
          printPaging(*ptr, nextVirt, indent + 1);
        }
      }
    }
    if(!visitedAny) {
      pline(spaces(indent), (uptr) &pt, ": This table was empty :(");
    }
  };

  // Sets `vidmode`
  void fetchMode(i16 mode) {
    asm("call getVideoMode" :: "c"(mode) : "ax", "edx", "di", "memory");
  }

  // Chose a mode
  void setMode(i16 mode) {
    asm("call setVideoMode" :: "b"(mode) : "ax", "edx");
  }

  void fetchMemoryRegion() {
    asm("call getMemoryMap" ::: "eax", "ebx", "ecx", "edx", "di", "memory");
  }
}

extern "C" void initializeDebug() {
  if constexpr(!quiet)
    flo::IO::VGA::clear();

  // We always initialize serial as other parts could be non-quiet
  flo::IO::serial1.initialize();
  flo::IO::serial2.initialize();
  flo::IO::serial3.initialize();
  flo::IO::serial4.initialize();

  assertAssumptions();
}

extern "C" void setupVideo() {
  pline("Picking VBE2 mode");
  pline("Adapter: ", vesa.product_name());
  pline("Available 4bpp linear framebuffer modes:");

  pickedDisplay.mode = 0xFFFF;

  for(auto mode = vesa.video_modes(); *mode != 0xFFFF; ++mode) {
    fetchMode(*mode);

    // No linear framebuffer support, skip
    if(!(vidmode.attributes & (1 << 7)))
      continue;

    // Verify bits per color is 4
    if(vidmode.bpp != 32)
      continue;

    pline("Mode: ", *mode, ", ", Decimal{vidmode.width}, "x", Decimal{vidmode.height});

    if(vidmode.width  == desiredWidth &&
       vidmode.height == desiredHeight) {
      pline("Found desired mode!");
    }
    else
      continue;

    pickedDisplay.mode   = *mode;
    pickedDisplay.width  = vidmode.width;
    pickedDisplay.height = vidmode.height;
    pickedDisplay.pitch  = vidmode.pitch;
    pickedDisplay.bpp    = vidmode.bpp / 8;
    pickedDisplay.framebuffer = vidmode.framebuffer;
    break;
  }

  if(pickedDisplay.mode == 0xFFFF) {
    pline("Please set one of the above modes as your desired mode.");
    flo::CPU::hang();
  }

  setMode(pickedDisplay.mode);
  vgaDisabled = true;

  // draw some test pattern on the screen
  for(int y = 0; y < pickedDisplay.height; ++ y)
  for(int x = 0; x < pickedDisplay.width;  ++ x) {
    auto col = x % 8 == 0 || y % 8 == 0 ? 1 : 0;
    auto offset = y * pickedDisplay.pitch + x * pickedDisplay.bpp;
    *(u8*)(pickedDisplay.framebuffer + offset + 0) = col ? 0x24 : 0;
    *(u8*)(pickedDisplay.framebuffer + offset + 1) = col ? 0x3d : 0;
    *(u8*)(pickedDisplay.framebuffer + offset + 2) = col ? 0xdc : 0;
  }
}

extern "C" [[noreturn]] void printVideoModeError() {
  char *error;
  asm("":"=a"(error));
  pline("There was an error initializing the display!");
  pline("Error supplied: ", error);

  flo::CPU::hang();
}

auto physHigh = minMemory;

void consumeMemory(MemoryRange &range) {
  // Make sure we're not taking any memory we're loaded into, we can't
  // use them for our free list as we need to write to them.
  range.begin = std::max(minMemory, range.begin);

  if(physHigh < range.end)
    physHigh = range.end;

  // First align the memory to whole pages
  range.begin = flo::Paging::alignPageUp(range.begin);
  range.end   = flo::Paging::alignPageDown(range.end);

  // We'll consume the low memory (below 4 GB) before going to 64 bit.
  auto constexpr maxMemory = flo::PhysicalAddress{1} << 32ull;

  auto processLater = [](MemoryRange &&mem) {
    pline(" Saving ", mem.begin(), " to ", mem.end(), " for later");
    if(highMemRanges.size() < highMemRanges.max_size())
      highMemRanges.emplace_back(std::move(mem));
  };

  if(range.end > maxMemory) {
    // This chunk ends in 64 bit memory.

    if(range.begin >= maxMemory)
      // It's entirely in 64 bit memory, just save it for later and ignore for now
      return processLater(std::move(range));

    // It's a little bit of both, split it.
    auto upper = range;
    upper.begin = maxMemory;
    range.end = maxMemory;
    processLater(std::move(upper));
  }

  pline(" Consuming ", range.begin(), " to ", range.end(), " right now");

  // Consume the memory, nom nom
  for(; range.begin < range.end; range.begin += flo::PhysicalAddress{flo::Paging::PageSize<1>})
    *(u64*)range.begin() = std::exchange(physicalFreeList, range.begin);
}

extern "C" void setupMemory() {
  do {
    fetchMemoryRegion();

    pline(shouldUse(mem) ? "U":"Not u", "sing memory of size ", mem.size(), " at ", mem.base());
    if(shouldUse(mem)) {
      MemoryRange mr;
      mr.begin = mem.base;
      mr.end = mem.base + mem.size;
      consumeMemory(mr);
    }
  } while(mem.savedEbx);
}

namespace {
  // 3 -> aligned to 1GB, 2 -> aligned to 2MB, 1 -> aligned to 4KB etc
  // Every level higher alignment means one factor of 512 less memory overhead
  // but also 9 less bits of entropy.
  // That means lower numbers are more secure but also take more memory.
  constexpr auto kaslrAlignmentLevel = 2;

  flo::VirtualAddress randomizeKASLRBase() {
  redo:
    // We're currently running in 32 bit so we have to generate 32 bits at a time
    auto base = flo::VirtualAddress{((u64)flo::random32() << 32) | flo::random32()};

    // Start at possible addresses at 8 GB, we don't wan't to map the lower 4 GB
    if(base < flo::VirtualAddress{2ull << 32})
      goto redo;

    // Make sure we're in the lower half of virtual memory, we want space for any amount of physical memory.
    // Half of the virtual address space better be enough.
    base %= (flo::Paging::maxUaddr) >> 1ull;

    base = flo::Paging::alignPageDown<kaslrAlignmentLevel>(base);

    // Make the pointer canonical
    base = flo::Paging::makeCanonical(base);

    return base;
  }
}

extern "C" void doEarlyPaging() {
  // We will locate the physical memory at this point
  if constexpr(disableKASLR) {
    kaslrBase = flo::VirtualAddress{1ull << 34};
  } else {
    kaslrBase = randomizeKASLRBase();
  }
  pline("KASLR base: ", kaslrBase());
  physicalVirtBase = kaslrBase;

  using PageRoot = flo::Paging::PageTable<flo::Paging::PageTableLevels>;

  // Prepare the paging root
  auto &pageRootPhys = *new ((PageRoot*) flo::getPhysicalPage()()) PageRoot();

  // Set the paging root
  asm("mov %0, %%cr3" :: "Nd"(&pageRootPhys));
  pline("New paging root: ", &pageRootPhys, ", ", flo::Paging::getPagingRoot());

  // Align the physical memory size
  physHigh = flo::Paging::alignPageUp<kaslrAlignmentLevel>(physHigh);

  flo::Paging::Permissions permissions;
  permissions.writeEnable = 1;
  permissions.allowUserAccess = 0;
  permissions.writethrough = 0;
  permissions.disableCache = 0;
  permissions.mapping.global = 0;
  permissions.mapping.exectueDisable = 1;

  auto err =
    flo::Paging::map(
      flo::PhysicalAddress{0}, kaslrBase, physHigh, permissions,
      [](auto ...vals) { pline(std::forward<decltype(vals)>(vals)...); }
    );

  if(!err) {
    permissions.mapping.exectueDisable = 0;

    err = flo::Paging::map(
      flo::PhysicalAddress{0}, flo::VirtualAddress{0}, physHigh, permissions,
      [](auto ...vals) { pline(std::forward<decltype(vals)>(vals)...); }
    );
  }

  printPaging(pageRootPhys);
  flo::checkMappingError(err, [](auto ...vals) {
    pline(std::forward<decltype(vals)>(vals)...);
  }, flo::CPU::hang);

  pline("Successfully mapped physical memory!");
}

namespace {
  u8 diskReadCode;

  void checkReadError() {
    char const *errstr = flo::BIOS::int0x13err(diskReadCode);
    if(errstr) {
      pline("Disk read error: ", errstr);
      flo::CPU::hang();
    }
  }

  u8 *readDisk(u64 sector) {
    dap.sectorToRead = sector;
    asm volatile("call readDisk" :::  "eax", "ebx", "ecx", "edx", "si", "memory");
    checkReadError();
    return diskdata;
  }

  void doLoadLoader(u32 startingSector, u32 numPages) {
    auto outAddr = flo::VirtualAddress{flo::Util::mega(512)};
    loaderStack = outAddr;
    pline("Kernel loader (", Decimal{numPages}, " page(s)) at ", outAddr());

    // RWX, supervisor only
    flo::Paging::Permissions perms;
    perms.writeEnable = 1;
    perms.allowUserAccess = 0;
    perms.writethrough = 0;
    perms.disableCache = 0;
    perms.mapping.exectueDisable = 0;
    u64 *physFreeWriteLoc = nullptr;

    auto rewriteLoaderHeader =
      [&, passedMagic = false, entryFound = false](u64 *mem) mutable {
        u64 ind = 0;

        if(std::exchange(passedMagic, true))
          ind += 2;

        while(ind != flo::IO::Disk::SectorSize/8 && !entryFound) {
          switch(mem[ind]) {
            break; case flo::Util::genMagic("FLORKLOD"):
              // Calculate the virtual address this is loaded at
              kernelLoaderEntry = outAddr + flo::VirtualAddress{(ind + 1) * 8};
              pline("Kernel loader entry: ", kernelLoaderEntry);
              entryFound = true;

            break; case flo::Util::genMagic("PhysFree"):
              physFreeWriteLoc = &mem[ind];

            break; case flo::Util::genMagic("PhysBase"):
              (flo::VirtualAddress &)mem[ind] = kaslrBase;

            break; case flo::Util::genMagic("HighFree"):

            break; case flo::Util::genMagic("DispWide"):
              mem[ind] = pickedDisplay.width;

            break; case flo::Util::genMagic("DispHigh"):
              mem[ind] = pickedDisplay.height;

            break; case flo::Util::genMagic("DispPitc"):
              mem[ind] = pickedDisplay.pitch;

            break; case flo::Util::genMagic("FrameBuf"):
              mem[ind] = pickedDisplay.framebuffer;

            break; case flo::Util::genMagic("DriveNum"):
              mem[ind] = diskNum;

            break; default: // Unknown magic
              mem[ind] = flo::Util::genMagic("UNKNOMAG");
          }
          ++ind;
        }
      };

    for(u32 i = 0; i < numPages; ++ i) {
      auto ppage = flo::getPhysicalPage();

      for(u32 offs = 0; offs < flo::Paging::PageSize<1>; offs += flo::IO::Disk::SectorSize) {
        flo::Util::copymem(flo::getPhys<u8>(ppage) + offs, diskdata, flo::IO::Disk::SectorSize);

        rewriteLoaderHeader((u64*)(ppage() + offs));

        readDisk(++startingSector);
      }

      auto err = flo::Paging::map(ppage, outAddr, flo::Paging::PageSize<1>, perms);
      flo::checkMappingError(err, [](auto ...vals) {
        pline(std::forward<decltype(vals)>(vals)...);
      }, flo::CPU::hang);

      outAddr += flo::VirtualAddress{flo::Paging::PageSize<1>};
    }

    // We cannot use `getPhysicalPage()` after this point, that would invalidate the list given to the next stage.
    if(physFreeWriteLoc) {
      *physFreeWriteLoc = physicalFreeList();
    } else {
      pline("Physical base entry missing in kernel loader header!");
    }

    if(!kernelLoaderEntry) {
      pline("Could not find kernel loader entry, stopping!");
      flo::CPU::hang();
    }

    perms.writeEnable = 1;
    perms.allowUserAccess = 0;
    perms.writethrough = 0;
    perms.disableCache = 0;
    perms.mapping.exectueDisable = 1;

    // Make a stack for the loader
    auto err = flo::Paging::map(loaderStack - flo::VirtualAddress{0x20000}, 0x20000, perms);
    flo::checkMappingError(err, [](auto ...vals) {
      pline(std::forward<decltype(vals)>(vals)...);
    }, flo::CPU::hang);
    pline("Mapped stack for loader");
  }
}

extern "C" void loadKernelLoader() {
  pline("Loading kernel loader...");

  u8 const magic[16] {
    0x09, 0xF9, 0x11, 0x02, 0x9D, 0x74, 0xE3, 0x5B,
    0xD8, 0x41, 0x56, 0xC5, 0x63, 0x56, 0x88, 0xC0,
  };

  for(u32 loaderSector = 0; loaderSector < 1000; ++loaderSector) {
    readDisk(loaderSector);

    if(flo::Util::memeq(magic, diskdata, sizeof(magic))) {
      pline("Kernel loader found at sector ", Decimal{loaderSector});

      u32 loaderPages = flo::Util::get<u32>(diskdata, sizeof(magic));
      u64 loaderSize = loaderPages * flo::Paging::PageSize<1>;
      pline("Kernel loader with size ", Decimal{loaderPages}, ", ", loaderSize);

      doLoadLoader(loaderSector, loaderPages);
      return;
    }
  }
  pline("Kernel loader not found in first 1000 sectors of disk. Giving up.");
  flo::CPU::hang();
}

extern "C" void prepare64() {

  u32 cr4;
  // Enable PAE
  asm("mov %%cr4, %0" :  "=r"(cr4));
  pline("CR4: ", cr4);
  cr4 |= (1 << 5);
  pline("CR4: ", cr4);
  asm("mov %0, %%cr4" :: "Nd"(cr4));

  u32 efer;
  // Enable long mode and WX
  asm("rdmsr" : "=a"(efer) : "c"(0xC0000080)); // Bit 8: LM, Bit 11: NX
  pline("IA32_EFER: ", efer);
  efer |= (1 << 8) | (1 << 11);
  pline("IA32_EFER: ", efer);
  asm("wrmsr" :            : "c"(0xC0000080), "a"(efer));

  u32 cr0;
  // Enable paging
  asm("mov %%cr0, %0" :  "=r"(cr0));
  pline("CR0: ", cr0);
  cr0 |= (1 << 31);
  pline("CR0: ", cr0);
  //asm("mov %0, %%cr0" :: "Nd"(cr0));

  asm("jmp .");

  flo::CPU::hang();


  /*
    # Enable PAE
  mov eax, cr4
  or  eax, 1 << 5
  mov cr4, eax

  # Enable long mode and NX
  mov ecx, 0xC0000080 # EFER MSR
  rdmsr
  or  eax, 1 << 8  # LM bit
  or  eax, 1 << 11 # NX bit
  wrmsr

  # jmp .

  # Enable paging
  mov eax, cr0
  or  eax, 1 << 31
  mov cr0, eax
  */
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

flo::PhysicalAddress flo::getPhysicalPage() {
  return std::exchange(physicalFreeList, *(flo::PhysicalAddress *)physicalFreeList());
}
