#include "flo/Paging.hpp"

#include "flo/Algorithm.hpp"
#include "flo/Assert.hpp"
#include "flo/Bitfields.hpp"
#include "flo/CPU.hpp"
#include "flo/IO.hpp"

#include "flo/Containers/Array.hpp"
#include "flo/Containers/Optional.hpp"

namespace flo::Paging {
  namespace {
    constexpr bool quiet = false;
    auto pline = flo::makePline<quiet>("[PAGING]");

    struct Arch_page_table;

#ifdef FLO_ARCH_X86_64
    flo::PhysicalAddress arch_get_paging_root() { return flo::CPU::cr3; }
    void arch_set_paging_root(flo::PhysicalAddress phys) { flo::CPU::cr3 = phys; }

    /* Default constructor must make an non-present entry */
    struct Arch_table_entry {
      Arch_table_entry(): rep{0} { }

      bool is_mapping() const {
        return data.is_mapping;
      }

      bool is_present() const {
         return data.present;
      }

      bool readable() const {
        return is_present();
      }

      bool writeable() const {
        return data.writeable;
      }

      bool executable() const {
        return !data.execute_disable;
      }

      bool global() const {
        return data.allow_userspace;
      }

      Arch_page_table &get_table() const {
        assert(!is_mapping());
        return *flo::getPhys<Arch_page_table>(get_physaddr());
      }

      u64 repr() const {
        return rep;
      }

      void add_table_permissions(flo::Paging::Permissions const &perms) {
        // Permissions which are checked at table level needs to be applied here too
        if(perms.executable)
          data.execute_disable = 0;
        if(perms.writeable)
          data.writeable = 1;
      }

      void make_mapping(flo::PhysicalAddress phys, flo::Paging::Permissions const &perms) {
        assert(!is_present());

        data.present = 1;
        data.is_mapping = 1;

        apply_permissions(perms);
        set_physaddr(phys);
      }

      void make_page_table(flo::Paging::Permissions const &perms) {
        assert(!is_present());

        data.present = 1;
        data.is_mapping = 0;

        apply_permissions(perms);
        set_physaddr(flo::physFree.getPhysicalPage(1));
        // Clear page table
        flo::Util::setmem(getPhys<u8>(get_physaddr()), 0, flo::Paging::PageSize<1>);
      }

      flo::PhysicalAddress get_physaddr() const {
        return flo::PhysicalAddress{data.physaddr << data.physaddr.startBit};
      }

      void clear() {
        rep = 0;
      }

    private:
      void apply_permissions(flo::Paging::Permissions const &perms) {
        data.execute_disable = !perms.executable;
        data.writeable = perms.writeable;

        if(is_mapping()) {
          data.writethrough = perms.writethrough;
          data.disable_caching = !perms.cacheable;
          data.allow_userspace = perms.userspace;
        }
        else {
          data.writethrough = 1;
          data.disable_caching = 0;
          data.allow_userspace = 0;
        }
      }

      void set_physaddr(flo::PhysicalAddress phys) {
        data.physaddr = phys() >> data.physaddr.startBit;
      }

      union {
        u64 rep;

        union {
          flo::Bitfield<0, 1> present;
          flo::Bitfield<1, 1> writeable;
          flo::Bitfield<2, 1> allow_userspace;
          flo::Bitfield<3, 1> writethrough;
          flo::Bitfield<4, 1> disable_caching;
          flo::Bitfield<5, 1> accessed;
          flo::Bitfield<7, 1> is_mapping; // Technically ignored on paging level 1, but we keep it accurate
          flo::Bitfield<63, 1> execute_disable;

          union {
            // Points to one page of another page table
            flo::Bitfield<8, 4> ignored;
          } pageTable;

          union {
            flo::Bitfield<6, 1> dirty;
            flo::Bitfield<8, 1> global;
            flo::Bitfield<9, 3> ignored;
          } mapping;

          flo::Bitfield<flo::Paging::pageOffsetBits<1>, flo::Paging::maxPhysBits - flo::Paging::pageOffsetBits<1>> physaddr;
        } data;
      };
    };
#endif

    struct Arch_page_table: flo::Array<Arch_table_entry, flo::Paging::PageTableSize> { };

    static_assert(sizeof(Arch_page_table) == flo::Paging::PageSize<1>, "Expected page tables to be exactly one page large.");

    void print(Arch_table_entry const &e, int level, flo::VirtualAddress vaddr) {
      if(level < 1)
        return;
      flo::Paging::pline(
        vaddr, ": ",
        flo::spaces(flo::Paging::PageTableLevels - level),
        e.is_mapping() ? "Mapping" : "Table",
        " -> ", e.get_physaddr(), ": ",
        e.readable() ? "r" : "-",
        e.writeable() ? "w" : "-",
        e.executable() ? "x" : "-",
        e.global() ? "g" : "-",
        ", raw: ", e.repr()
      );
    }

    void do_print_table(Arch_page_table &table, int level, flo::VirtualAddress vaddr) {
      bool visited_any = false;
      for(auto &entry: table) {
        if(entry.is_present()) {
          visited_any = true;
          print(entry, level, vaddr);
          if(!entry.is_mapping()) {
            if(level == 1)
              flo::Paging::pline("WARNING: TABLE AT LEVEL 1!");
            else
              do_print_table(entry.get_table(), level - 1, vaddr);
          }
        }
        vaddr += flo::VirtualAddress{flo::Paging::pageSizes[level - 1]};
        vaddr = flo::Paging::make_canonical(vaddr);
      }
      if(!visited_any)
        flo::Paging::pline("Warning: No entries in page table");
    }
  }

    template<int level>
    Arch_table_entry &get_table_entry(flo::VirtualAddress virt, Arch_page_table &table) {
      return table[(virt() >> flo::Paging::pageOffsetBits<level>) % flo::Paging::PageTableSize];
    }

    template<int currentLevel, int targetLevel>
    Arch_table_entry &make_tables(flo::VirtualAddress virt, flo::Paging::Permissions const &perms, Arch_page_table &table) {
      auto &entry = get_table_entry<currentLevel>(virt, table);

      if constexpr(currentLevel == targetLevel)
        return entry;

      else {
        if(!entry.is_present()) {
          entry.make_page_table(perms);
          return make_tables<currentLevel - 1, targetLevel>(virt, perms, entry.get_table());
        }
        else {
          assert_err(!entry.is_mapping(), "Overlapping mappings!");
          entry.add_table_permissions(perms);
          return make_tables<currentLevel - 1, targetLevel>(virt, perms, entry.get_table());
        }
      }
    }

    template<int level>
    void do_map_at(flo::VirtualAddress virt, flo::Paging::Permissions const &perms, Arch_page_table &root, flo::Optional<flo::PhysicalAddress> &phys) {
      auto &entry = make_tables<flo::Paging::PageTableLevels, level>(virt, perms, root);
      if(entry.is_present()) {
        pline("Already something here!");
        do_print_table(root, flo::Paging::PageTableLevels, flo::VirtualAddress{0});
        assert_not_reached();
      }
      entry.make_mapping(phys ? *phys : flo::physFree.getPhysicalPage(level), perms);
    }

    template<int level>
    void try_map(flo::VirtualAddress &virt, u64 &size, flo::Paging::Permissions const &perms, Arch_page_table &root, flo::Optional<flo::PhysicalAddress> &phys) {
      if constexpr(level < 1) {
        if(phys)
          pline("Could not map ", virt, ", size ", size, " or phys ", *phys);
        else
          pline("Could not map ", virt, ", or size ", size);
        assert_not_reached();
      } else {
        constexpr auto step = flo::Paging::PageSize<level>;

        if(size < step)
          return try_map<level - 1>(virt, size, perms, root, phys);

        if(virt() % step)
          return try_map<level - 1>(virt, size, perms, root, phys);

        if(phys && (*phys)() % step)
          return try_map<level - 1>(virt, size, perms, root, phys);

        do_map_at<level>(virt, perms, root, phys);

        size -= step;
        virt += flo::VirtualAddress{step};
        if(phys) *phys += flo::PhysicalAddress{step};
      }
    }

    void do_map_loop(flo::VirtualAddress virt, u64 size, flo::Paging::Permissions const &perms, Arch_page_table &root, flo::Optional<flo::PhysicalAddress> phys) {
      assert(perms.readable);
      while(size)
        try_map<flo::Paging::PageTableLevels>(virt, size, perms, root, phys);
      assert(!size);
    }

    template<int level>
    void do_set_perms(flo::VirtualAddress &virt, u64 &size, flo::Paging::Permissions const &perms, Arch_page_table &table) {
      if constexpr(level < 1) {
        assert_not_reached();
      }
      else {
        while(size) {
          constexpr auto step = flo::Paging::PageSize<level>;
          auto &entry = get_table_entry<level>(virt, table);

          assert(entry.is_present());
          if(entry.is_mapping()) {
            assert(step <= size);
            auto phys = entry.get_physaddr();
            entry.clear();
            entry.make_mapping(phys, perms);
            size -= step;
            virt += flo::VirtualAddress{step};
          } else {
            entry.add_table_permissions(perms);
            do_set_perms<level - 1>(virt, size, perms, entry.get_table());
          }
        }
      }
    }

    template<int level>
    void try_unmap_at(flo::VirtualAddress &virt, u64 &size, bool recycle_pages, Arch_page_table &table) {
      auto constexpr step_size = flo::Paging::PageSize<level>;

      auto &entry = get_table_entry<level>(virt, table);

      auto step = [&]() {
        virt += flo::VirtualAddress{step_size};
        size -= step_size;
      };

      if(!entry.is_present())
        return step();

      if(entry.is_mapping()) {
        assert_err(step_size <= size, "lol partial unmapping of large pages not implemented yeeeeet");
        if(recycle_pages)
          flo::physFree.returnPhysicalPage(entry.get_physaddr(), level);
        entry.clear();
        return step();
      }
      if constexpr(level > 1) {
        auto next_table = entry.get_table();
        try_unmap_at<level - 1>(virt, size, recycle_pages, next_table);
        auto any_present = flo::anyOf(next_table.begin(), next_table.end(), [](auto &e) { return e.is_present(); });
        if(!any_present) {
          flo::physFree.returnPhysicalPage(entry.get_physaddr(), 1);
          entry.clear();
        }
      }
      else {
        assert_err(false, "Found table at level 1 while unmapping");
      }
    }

    void page_tables_modified(flo::PhysicalAddress root) {
      // If we edited our current page table, reload it.
      if(root == flo::Paging::get_current_root()) {
        flo::Paging::set_root(flo::Paging::get_current_root());
      }
    }
}

flo::PhysicalAddress flo::Paging::get_current_root() { return arch_get_paging_root(); }
void flo::Paging::set_root(flo::PhysicalAddress phys) { arch_set_paging_root(phys); }

void flo::Paging::map(flo::Paging::Impl::Map_regular_args const &args) {
  do_map_loop(args.virt, args.size, args.perm, *flo::getPhys<Arch_page_table>(args.root), flo::nullopt);
}

void flo::Paging::map_phys(flo::Paging::Impl::Map_phys_args const &args) {
  do_map_loop(args.virt, args.size, args.perm, *flo::getPhys<Arch_page_table>(args.root), args.phys);
}

void flo::Paging::unmap(flo::Paging::Impl::Unmap_args const &args_) {
  auto args = args_;
  while(args.size)
    try_unmap_at<flo::Paging::PageTableLevels>(args.virt, args.size, args.recycle_pages, *flo::getPhys<Arch_page_table>(args.root));

  page_tables_modified(args.root);
}

//flo::Paging::Permissions flo::Paging::permissions(Impl::Permission_args const &) { }

void flo::Paging::print_memory_map(flo::Paging::Impl::PrintArgs const &args) {
  do_print_table(*flo::getPhys<Arch_page_table>(args.root), flo::Paging::PageTableLevels, flo::VirtualAddress{0});
}

void flo::Paging::set_perms(flo::Paging::Impl::Map_regular_args const &args_) {
  auto args = args_;
  do_set_perms<flo::Paging::PageTableLevels>(args.virt, args.size, args.perm, *flo::getPhys<Arch_page_table>(args.root));

  page_tables_modified(args.root);
}

flo::PhysicalAddress flo::Paging::make_paging_root() {
  auto value = flo::physFree.getPhysicalPage(1);
  for(auto &e: *flo::getPhys<Arch_page_table>(value))
    e.clear();
  return value;
}
