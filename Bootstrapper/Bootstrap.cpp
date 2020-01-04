#include "Bootstrap.hpp"
#include "Bootstrapper.hpp"

#include "flo/CPU.hpp"
#include "flo/Paging.hpp"
#include "flo/Random.hpp"
#include "flo/Serial.hpp"
#include "flo/Bitfields.hpp"

#include <algorithm>

#include <algorithm>

using Constructor = void(*)();

extern "C" Constructor constructorsStart;
extern "C" Constructor constructorsEnd;

extern "C" void doConstructors() {
  std::for_each(&constructorsStart, &constructorsEnd, [](Constructor c){
    (*c)();
  });
}

namespace {
  constexpr bool quiet = false;

  int currX = 0;
  int currY = 0;

  constexpr auto VGAWidth = 80, VGAHeight = 25;

  volatile u16 *charaddr(int x, int y) {
    return (volatile u16 *)0xB8000 + (y * VGAWidth + x);
  }

  enum struct Color {
    red,
    cyan,
    yellow,
    white,
  };

  u8 currentVGAColor;

  void setchar(int x, int y, char c) {
    *charaddr(x, y) = (currentVGAColor << 8) | c;
  }

  void setchar(int x, int y, u16 entireChar) {
    *charaddr(x, y) = entireChar;
  }

  u16 getchar(int x, int y) {
    return *charaddr(x, y);
  }

  void vgaFeedLine() {
    currX = 0;
    if(currY == VGAHeight - 1) {
      // Scroll
      for(int i = 0; i < VGAHeight - 1; ++ i) for(int x = 0; x < VGAWidth; ++ x)
          setchar(x, i, getchar(x, i + 1));

      // Clear bottom line
      for(int x = 0; x < VGAWidth; ++ x)
        setchar(x, VGAHeight - 1, ' ');
    }
    else
      ++currY;
  }

  bool escaping = false;
  void vgaPutchar(char c) {
    if(c == '\n')
      return vgaFeedLine();
    if(currX == VGAWidth)
      vgaFeedLine();

    setchar(currX++, currY, c);
  }
}

namespace {
  bool vgaDisabled = false;

  void putchar(char c){
    if constexpr(!quiet) {
      flo::serial1.write(c);
      if(!vgaDisabled && !escaping)
        vgaPutchar(c);
    }
  }

  void feedLine() {
    if constexpr(!quiet) {
      flo::serial1.write('\n');
      if(!vgaDisabled)
        vgaFeedLine();
    }
  }

  void print(char const *str) {
    while(*str)
      putchar(*str++);
  }

  void setColor(char const *colorStr) {
    escaping = true;
    print("\x1b[");
    print(colorStr);
    print("m");
    escaping = false;
  }

  void setRed() {
    currentVGAColor = 0x4;
    setColor("31");
  }

  void setYellow() {
    currentVGAColor = 0xE;
    setColor("33");
  }

  void setCyan() {
    currentVGAColor = 0x3;
    setColor("36");
  }

  void setWhite() {
    currentVGAColor = 0x7;
    setColor("37");
  }

  void setBlue() {
    currentVGAColor = 0x1;
    setColor("34");
  }

  template<bool removeLeadingZeroes = false, bool prefix = false, typename T>
  auto printNum(T num) {
    auto constexpr numChars = std::numeric_limits<T>::digits/4;

    std::array<char, numChars + 1> buf{};
    auto it = buf.rbegin() + 1;
    while(it != buf.rend()) {
      *it++ = "0123456789ABCDEF"[num & T{0xf}];
      num >>= 4;

      if constexpr(removeLeadingZeroes) if(!num)
        break;
    }

    if constexpr(prefix)
      print("0x");
    return print(&*--it);
  }

  template<typename T>
  auto printDec(T num) {
    std::array<char, std::numeric_limits<T>::digits10 + 1> buf{};
    auto it = buf.rbegin();
    do {
      *++it = '0' + (num % 10);
      num /= 10;
    } while(num);

    return print(&*it);
  }

  template<typename T>
  struct Dec { T val; };
  template<typename T>
  Dec(T) -> Dec<T>;

  template<typename T>
  struct IsDec { static constexpr bool value = false; };
  template<typename T>
  struct IsDec<Dec<T>> { static constexpr bool value = true; };

  template <typename ...Ts>
  void pline(Ts &&...vs) {
    auto p = [](auto &&val) {
      if constexpr(IsDec<std::decay_t<decltype(val)>>::value) {
        setYellow();
        return printDec(val.val);
      }
      else if constexpr(std::is_convertible_v<decltype(val), char const *>) {
        setWhite();
        return print(val);
      }
      else if constexpr(std::is_pointer_v<std::decay_t<decltype(val)>>) {
        setBlue();
        return printNum(reinterpret_cast<uptr>(val));
      }
      else {
        setCyan();
        return printNum(val);
      }
    };

    setRed();
    print("[FBTS] ");
    (p(std::forward<Ts>(vs)), ...);
    feedLine();
  }

  template<typename T>
  struct RealPtr {
    u16 offset;
    u16 segment;

    T *operator()() const { return reinterpret_cast<T *>(offset + (segment << 4)); }
  } __attribute__((packed));

  struct VesaInfo {
    char signature[4];
    u8 versionMinor, versionMajor;
    RealPtr<char> oem;
    u32 capabilities;
    RealPtr<u16> video_modes;
    u16 video_memory;
    u16 software_rev;
    RealPtr<char> vendor;
    RealPtr<char> product_name;
    RealPtr<char> product_rev;
  } __attribute__((packed));

  struct VideoMode {
    u16 attributes;
    u8  window_a;
    u8  window_b;
    u16 granularity;
    u16 window_size;
    u16 segment_a;
    u16 segment_b;
    u32 win_func_ptr;
    u16 pitch; // Bytes per line
    u16 width;
    u16 height;
    u8  w_char;
    u8  y_char;
    u8  planes;
    u8  bpp; // Bits per pixel
    u8  banks;
    u8  memory_model;
    u8  bank_size;
    u8  image_pages;
    u8  reserved0;
   
    u8  red_mask;
    u8  red_position;
    u8  green_mask;
    u8  green_position;
    u8  blue_mask;
    u8  blue_position;
    u8  reserved_mask;
    u8  reserved_position;
    u8  direct_color_attributes;
   
    u32 framebuffer;
    u32 off_screen_mem_off;
    u16 off_screen_mem_size;
  } __attribute__((packed));

  namespace ExtendedAttribs {
    enum : u32 {
      Ignore = 1,
      NonVolatile = 2,
    };
  }

  struct MemmapEntry {
    flo::PhysicalAddress base;
    flo::PhysicalAddress size;

    enum struct RegionType: u32 {
      Usable = 1,
      Reserved = 2,
      ACPIReclaimable = 3,
      ACPINonReclaimable = 4,
      Bad = 5,
    } type;

    u32 attribs;

    u32 savedEbx;
    u16 bytesFetched;
  };

  bool shouldUse(MemmapEntry const &ent) {
    if(ent.type != MemmapEntry::RegionType::Usable)
      return false;

    if(ent.bytesFetched > 20)
      if(ent.attribs & (ExtendedAttribs::Ignore | ExtendedAttribs::NonVolatile))
        return false;

    return true;
  }

  void assertAssumptions() {
    // Check if the CPU supports 5 level paging
    u32 ecx;
    asm("cpuid":"=c"(ecx):"a"(7),"c"(0));
    bool supports5lvls = ecx & (1 << 16);
    pline("5 level paging is ", supports5lvls ? "" : "not", " supported by your CPU");
    if constexpr(flo::Paging::PageTableLevels == 4) if( supports5lvls) {
      pline("Please rebuild florence with 5 level paging support for security reasons");
      pline("You will gain an additional 9 bits of KASLR :)");
    }
    if constexpr(flo::Paging::PageTableLevels == 5) if(!supports5lvls) {
      pline("Florence was built with 5 level paging support, we cannot continue");
      flo::CPU::hang();
    }
  }
}

extern "C" void initializeDebug() {
  flo::serial1.initialize();
  flo::serial2.initialize();
  flo::serial3.initialize();
  flo::serial4.initialize();

  if constexpr(!quiet) {
    for(int x = 0; x < VGAWidth;  ++ x)
    for(int y = 0; y < VGAHeight; ++ y)
      setchar(x, y, ' ');
  }

  assertAssumptions();
}

extern "C" void rdrandError() {
  pline("ERROR: Your CPU is missing RDRAND support."),
  pline("Please run Florence with a more modern CPU.");
  pline("If using KVM, use flag \"-cpu host\".");

  flo::CPU::hang();
}

extern "C" union { struct VesaInfo vesa; struct MemmapEntry mem; } biosBuf;
auto &vesa = biosBuf.vesa;
auto &mem  = biosBuf.mem;
extern "C" struct VideoMode currentModeBuf;
extern "C" {
  flo::Displayinfo pickedDisplay;
}

namespace {
  // This magic function switches back to 16 bits 
  // and fetches the mode info, switches back to 32 bits
  // and then returns. Don't ask any questions.

  // The mode switch to 16 bits and back clobbers edx
  // The BIOS calls clobber ax
  // di and memory are clobbered by the bios call to get a video mode.

  void fetchMode(i16 mode) {
    asm("call getVideoMode" :: "c"(mode) : "ax", "edx", "di", "memory");
  }

  // Same thing goes here, but just sets it.
  void setMode(i16 mode) {
    asm("call setVideoMode" :: "b"(mode) : "ax", "edx");
  }
}

extern "C" u16 desiredWidth;
extern "C" u16 desiredHeight;

extern "C" void setupVideo() {
  pline("Picking VBE2 mode");
  pline("Adapter: ", vesa.product_name());
  pline("Available 4bpp linear framebuffer modes:");

  pickedDisplay.mode = 0xFFFF;

  for(auto mode = vesa.video_modes(); *mode != 0xFFFF; ++mode) {
    fetchMode(*mode);

    // No linear framebuffer support, skip
    if(!(currentModeBuf.attributes & (1 << 7)))
      continue;

    // Verify bits per color is 4
    if(currentModeBuf.bpp != 32)
      continue;

    pline("Mode: ", *mode, ", ", Dec{currentModeBuf.width}, "x", Dec{currentModeBuf.height});

    if(currentModeBuf.width  == desiredWidth &&
       currentModeBuf.height == desiredHeight) {
      pline("Found desired mode!");
    }
    else
      continue;

    pickedDisplay.mode   = *mode;
    pickedDisplay.width  = currentModeBuf.width;
    pickedDisplay.height = currentModeBuf.height;
    pickedDisplay.pitch  = currentModeBuf.pitch;
    pickedDisplay.bpp    = currentModeBuf.bpp / 8;
    pickedDisplay.framebuffer = currentModeBuf.framebuffer;
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
    auto col = x % 8 == 0 || y % 8 == 0 ? 255 : 0;
    auto offset = y * pickedDisplay.pitch + x * pickedDisplay.bpp;
    *(u8*)(pickedDisplay.framebuffer + offset) = col;
  }
}

extern "C" [[noreturn]] void printVideoModeError() {
  char *error;
  asm("":"=a"(error));
  pline("There was an error initializing the display!");
  pline("Error supplied: ", error);

  flo::CPU::hang();
}

extern "C" [[noreturn]] void noLong() {
  pline("This doesn't look like a 64 bit CPU, we cannot proceed!");
  flo::CPU::hang();
}

namespace {
  void fetchMemoryRegion() {
    asm("call getMemoryMap" ::: "eax", "ebx", "ecx", "edx", "di", "memory");
  }
};

decltype(highMemRanges) highMemRanges;
decltype(physicalFreeList) physicalFreeList = flo::PhysicalAddress{0};
decltype(physicalVirtBase) physicalVirtBase;

extern char BootstrapEnd;
auto const minMemory = flo::PhysicalAddress{(u64)&BootstrapEnd};

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
  auto kaslrBase = randomizeKASLRBase();
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
  permissions.exectueDisable = 1;
  permissions.mapping.global = 1;

  char const spaceBuf[]{' ', ' ', ' ', ' ', ' ', ' ', '\x00'};
  auto spaces = [&spaceBuf](int numSpaces) {
    return &spaceBuf[6 - numSpaces];
  };

  auto printPaging = [&spaces, indent = 0](auto &pt, auto &self, u64 virtaddr) mutable {
    bool visitedAny = false;
    for(int i = 0; i < flo::Paging::PageTableSize; ++ i) {
      auto &ent = pt.table[i];
      if(!ent.present)
        continue;

      visitedAny = true;
      //This gets a little too noisy
      //pline(spaces(indent), "Entry ", Dec{i}, " at ", (u32)&ent," (", nextVirt, ", ", ent.rep, ") mapping to ", ent.isMapping() ? "physical addr " : "page table at physical ", ent.physaddr()());
      if(!ent.isMapping()) {
        if constexpr(ent.lvl < 2) {
          pline(spaces(indent + 1), "Present level 1 mapping without mapping bit set!!");
          continue;
        }
        else {
          auto nextVirt = flo::Paging::makeCanonical(virtaddr | ((u64)i << flo::Paging::pageOffsetBits<ent.lvl>));
          pline(spaces(indent), "Entry ", Dec{i}, " at ", (u32)&ent," (", nextVirt, ", ", ent.rep, ") mapping to page table at physical ", ent.physaddr()());
          ++ indent;
          auto ptr = flo::getPhys<flo::Paging::PageTable<ent.lvl - 1>>(ent.physaddr());
          self(*ptr, self, nextVirt);
          -- indent;
        }
      }
    }
    if(!visitedAny) {
      pline(spaces(indent), (uptr) &pt, ": This table was empty :(");
    }
  };

  auto err = flo::Paging::map(flo::PhysicalAddress{0}, kaslrBase, physHigh, permissions,
    [](auto ...vals) {
      pline(std::forward<decltype(vals)>(vals)...);
    }
  );

  printPaging(pageRootPhys, printPaging, 0);
  if(err) {
    pline("Error while mapping ", err->virt(), " to ", err->phys(), " at paging level ", Dec{err->level});
    switch(err->type) {
      case flo::Paging::MappingError::AlreadyMapped:
        pline(spaces(2), "Already mapped, ", "PT: ", err->alreadyMapped.pageTableWithMapping, ", ind = ", Dec{err->alreadyMapped.mappingIndex});
        break;
      case flo::Paging::MappingError::NoAlignment:
        pline(spaces(2), "Misaligned pointers!");
        break;
      default:
        pline(spaces(2), "Unknown error!");
        break;
    }

    flo::CPU::hang();
  } else {
    pline("Successfully mapped physical memory!");
  }
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
  pline("Providing physical page: ", getPhys<void *>(physicalFreeList));
  return std::exchange(physicalFreeList, *(flo::PhysicalAddress *)physicalFreeList());
}
