#pragma once

#include "Ints.hpp"

#include "flo/Florence.hpp"
#include "flo/Util.hpp"

namespace flo {
  namespace Paging {
#ifdef FLO_ARCH_X86_64
    // This is generally 4 but 5 is coming to the market...
    constexpr static u64 PageTableLevels = 4;

    // Current assumption of this file
    static_assert(4 <= PageTableLevels && PageTableLevels <= 5);

    constexpr u64 pageTableIndexBits = 9;

    constexpr u64 PageTableSize = 1ull << pageTableIndexBits;
    static_assert(PageTableSize == 512);

    constexpr int maxPhysBits = 52;
    constexpr u64 MaxPhysAddr = 1ull << maxPhysBits;

    template<int Level = 1>
    constexpr u64 pageOffsetBits = 12 + pageTableIndexBits * (Level - 1);
    template<int Level = 1>
    constexpr u64 PageSize = 1ull << pageOffsetBits<Level>;

    static_assert(PageSize<1> == 0x1000);
    static_assert(PageSize<1> == 4096);
#endif

    inline constexpr u64 pageSizes[] {
      PageSize<1>,
      PageSize<2>,
      PageSize<3>,
      PageSize<4>,
      PageSize<5>,
    };

    template<int Level = 1, typename T>
    auto constexpr align_page_down(T value) {
      return value & (T)~(PageSize<Level> - 1);
    }

    template<int Level = 1, typename T>
    auto constexpr align_page_up(T value) {
      return align_page_down<Level>(value + T{PageSize<Level> - 1});
    }

    VirtualAddress constexpr virt_limit{1ull << pageOffsetBits<PageTableLevels + 1>};

    template<typename T>
    T make_canonical(T ptr) {
      if((uptr)ptr & (virt_limit() >> 1ull))
        return reinterpret_cast<T>((uptr)ptr | ~((virt_limit()) - 1ull));
      else
        return reinterpret_cast<T>((uptr)ptr &  ((virt_limit()) - 1ull));
    }

    template<>
    inline VirtualAddress make_canonical<VirtualAddress>(VirtualAddress ptr) {
      if(ptr & (VirtualAddress{virt_limit} >> 1ull))
        return ptr | ~(VirtualAddress{virt_limit} - VirtualAddress{1});
      else
        return ptr & (VirtualAddress{virt_limit} - VirtualAddress{1});
    }

    struct Permissions {
      bool readable : 1;
      bool writeable : 1;
      bool executable : 1;
      bool userspace : 1;
      bool cacheable : 1;
      bool writethrough : 1;
      bool global : 1;
    };

    // Get the current paging root
    flo::PhysicalAddress get_current_root();

    // Set the new paging root
    void set_root(flo::PhysicalAddress new_root);

    namespace Impl {
      struct Map_regular_args {
        flo::VirtualAddress virt;
        u64 size;
        Permissions perm;
        flo::PhysicalAddress root = get_current_root();
      };
    }

    // Map any regular memory at address
    void map(Impl::Map_regular_args const &);

    namespace Impl {
      struct Map_phys_args {
        flo::PhysicalAddress phys;
        flo::VirtualAddress virt;
        u64 size;
        Permissions perm;
        flo::PhysicalAddress root = get_current_root();
      };
    }

    // Map physical memory at address
    void map_phys(Impl::Map_phys_args const &);

    namespace Impl {
      struct Unmap_args {
        flo::VirtualAddress virt;
        u64 size;
        bool recycle_pages;
        flo::PhysicalAddress root = get_current_root();
      };
    }

    // Unmap any mapped pages in virtual address range
    void unmap(Impl::Unmap_args const &);

    namespace Impl {
      struct Permission_args {
        flo::VirtualAddress virt;
        flo::PhysicalAddress root = get_current_root();
      };
    }

    // Get the permissions at a virtual address
    Permissions permissions(Impl::Permission_args const &);

    namespace Impl {
      struct PrintArgs {
        flo::PhysicalAddress root = get_current_root();
      };
    }

    // Print the page tables (for debugging)
    void print_memory_map(Impl::PrintArgs const &);

    namespace Impl {
      struct SetPermArgs {
        flo::PhysicalAddress root = get_current_root();
      };
    }

    // Print the page tables (for debugging)
    void set_perms(Impl::Map_regular_args const &);

    flo::PhysicalAddress make_paging_root();
  }
}
