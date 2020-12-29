#include "Ints.hpp"

#include "Kernel/IO.hpp"

#include "flo/Assert.hpp"
#include "flo/CPU.hpp"
#include "flo/ELF.hpp"
#include "flo/Memory.hpp"
#include "flo/Kernel.hpp"
#include "flo/Paging.hpp"
#include "flo/Containers/Optional.hpp"

extern "C" {
  void *kernel_entry;
  flo::KernelArguments kernel_args;
}

namespace {
  u64 physcal_mem_base;
  auto phys_mem_high = flo::PhysicalAddress{0};
}

namespace Stivale {
  namespace {
    auto pline = flo::makePline<false>("[STIVALE]");

    flo::ELF64Image kernelELF{};

    struct Memory_entry {
      u64 base;
      u64 length;
      u32 type;
      u32 unused;
    } __attribute__((packed));

    struct Module {
      u64 begin;
      u64 end;
      char name[128];
      Module *next;
    };

    struct Info {
      char const *cmdline;
      Memory_entry *memory_map;
      u64 memory_map_entries;
      u64 framebuffer_addr;      // Address of the framebuffer and related info
      u16 framebuffer_pitch;
      u16 framebuffer_width;
      u16 framebuffer_height;
      u16 framebuffer_bpp;
      u64 rsdp;
      u64 module_count;
      Module *modules;
      u64 epoch;
      u64 flags;
    } __attribute__((packed));

    void clear_screen(Info *info) {
      pline("Clearing fb @", info->framebuffer_addr);
      flo::Util::setmem((u8 *)info->framebuffer_addr, 0x00, info->framebuffer_pitch * info->framebuffer_height);
    }

    void print_memmap(Info *info) {
      pline("Memory map:");
      for(u64 i = 0; i < info->memory_map_entries; ++ i) {
        pline(" ", info->memory_map[i].base, " to ", info->memory_map[i].base + info->memory_map[i].length, ": ", info->memory_map[i].type);
      }
    }

    template<typename Handler>
    void for_each_memmap_entry(Info *info, flo::Optional<u32> desired_type, u64 min_addr, u64 max_addr, Handler &&handler) {
      for(u64 i = 0; i < info->memory_map_entries; ++ i) {
        auto const &entry = info->memory_map[i];

        if(entry.type != *desired_type)
          continue;

        if(entry.base + entry.length < min_addr)
          continue;

        if(max_addr < entry.base)
          continue;

        Memory_entry e = entry;

        if(e.base + e.length >= max_addr)
          e.length = max_addr - e.base;

        if(e.base < min_addr) {
          e.length -= min_addr - e.base;
          e.base = min_addr;
        }

        if(!e.length)
          continue;

        handler(flo::PhysicalAddress{e.base}, e.length);
      }
    }

    void consume_memmap(Info *info, u32 desired_type, u64 min_addr, u64 max_addr) {
      for_each_memmap_entry(info, desired_type, min_addr, max_addr, [](auto base, auto size) {
        flo::consumePhysicalMemory(base, size);
      });
    }

    void load_kernel(Info *info, Module const &module, u64 kaslr_base) {
      kernelELF.data = (u8 const *)module.begin;
      kernelELF.size = module.end - module.begin;

      kernelELF.verify();

      u64 addrHigh = 0;

      kernelELF.forEachProgramHeader([&](flo::ELF64::ProgramHeader const &header) {
        u64 sectionAddrHigh = flo::Paging::align_page_up(header.vaddr() + header.memSz);
        if(sectionAddrHigh > addrHigh)
          addrHigh = sectionAddrHigh;
      });

      addrHigh = flo::Paging::align_page_up<1>(addrHigh);

      kernelELF.loadOffset = kaslr_base - addrHigh;

      pline("Kernel verified");

      kernelELF.loadAll();

      kernel_entry = (void *)kernelELF.entry()();
      pline("Kernel loaded, entry point at ", kernel_entry, " and load offset ", kernelELF.loadOffset);

      kernel_args.type = flo::KernelArguments::BootType::Stivale;
      kernel_args.physBase = flo::VirtualAddress{kaslr_base};
      kernel_args.physEnd = flo::VirtualAddress{kaslr_base + phys_mem_high()};
      kernel_args.elfImage = &kernelELF;
      kernel_args.physFree = &flo::physFree;
      kernel_args.stivale_boot.rsdp = flo::PhysicalAddress{info->rsdp};
      kernel_args.stivale_boot.fb = flo::PhysicalAddress{info->framebuffer_addr};
      kernel_args.stivale_boot.pitch = info->framebuffer_pitch;
      kernel_args.stivale_boot.width = info->framebuffer_width;
      kernel_args.stivale_boot.height = info->framebuffer_height;
      kernel_args.stivale_boot.bpp = info->framebuffer_bpp;
    }

    void load_kernel(Info *info, u64 kaslr_base) {
      assert(info->module_count > 0);

      auto module = info->modules;

      for(u64 i = 0; i < info->module_count; ++ i, module = module->next) {
        if(flo::Util::memeq("Kernel", module->name, 6))
          return load_kernel(info, *module, kaslr_base);
      }

      assert_not_reached();
    }
  }
}

namespace {
  u64 do_own_paging(Stivale::Info *info) {
    for(u64 i = 0; i < info->memory_map_entries; ++ i) {
      auto top = info->memory_map[i].base + info->memory_map[i].length;
      if(top > phys_mem_high())
        phys_mem_high = flo::PhysicalAddress{top};
    }

    Stivale::pline("Max phys addr at ", phys_mem_high());

    auto kaslr_base = flo::bootstrap_aslr_base(phys_mem_high);

    Stivale::pline("KASLR base: ", kaslr_base());

    // Our new root page table/cr3
    auto page_root = flo::Paging::make_paging_root();

    flo::Paging::Permissions perm {
      .readable = 1,
      .writeable = 1,
      .executable = 1,
      .userspace = 0,
      .cacheable = 1,
      .writethrough = 1,
      .global = 0,
    };

    // First, we identity map the bottom 4G
    flo::Paging::map_phys({
      .phys = flo::PhysicalAddress{0},
      .virt = flo::VirtualAddress{0},
      .size = flo::Util::giga(4ull),
      .perm = perm,
      .root = page_root,
    });

    // Then we map the physical memory
    perm.executable = 0;
    flo::Paging::map_phys({
      .phys = flo::PhysicalAddress{0},
      .virt = kaslr_base,
      .size = phys_mem_high(),
      .perm = perm,
      .root = page_root,
    });

    // No-Execute Enable
    flo::CPU::IA32_EFER |= 1 << 11;

    // Actually use the new page table
    flo::Paging::set_root(page_root);
    physcal_mem_base = kaslr_base;

    // @TODO Consume high memory

    return kaslr_base();
  }
}

extern "C" void callGlobalConstructors();

// This max addr value just is due to a tomatboot bug, otherwise would be 4G, specified by stivale;
// https://github.com/TomatOrg/TomatBoot-UEFI/issues/11
// This is an arbitrary address where everything below it seems safe to use
constexpr auto high_mem_limit = 0x7f000000ULL;

extern "C"
void stivale_main(Stivale::Info *info) {
  callGlobalConstructors();

  assert(info);

  //Stivale::clear_screen(info);

  Stivale::pline("Booted from ", info->flags & 1 ? "BIOS" : "UEFI", " with command line args ", info->cmdline);

  //Stivale::print_memmap(info);

  // Min addr value specified by stivale
  Stivale::consume_memmap(info, 1, flo::Util::mega(1), high_mem_limit);

  auto kaslr_base = do_own_paging(info);

  Stivale::load_kernel(info, kaslr_base);
}

void flo::feedLine() {
  Kernel::IO::Debugout::feedLine();
}

void flo::putchar(char c) {
  if(c == '\n')
    return feedLine();
  Kernel::IO::Debugout::write(c);
}

void flo::setColor(flo::TextColor col) {
  Kernel::IO::Debugout::setColor(col);
}

u8 *flo::getPtrPhys(flo::PhysicalAddress addr) {
  return (u8 *)addr() + physcal_mem_base;
}
