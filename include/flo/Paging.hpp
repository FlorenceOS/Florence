#pragma once

#include "Ints.hpp"
#include "flo/Florence.hpp"
#include "flo/Util.hpp"
#include "flo/Bitfields.hpp"
#include "flo/CPU.hpp"

#include <array>
#include <cstring>
#include <optional>

namespace flo {
  namespace Paging {
    constexpr inline bool noisy = false;

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

    inline constexpr u64 pageSizes[] {
      PageSize<1>,
      PageSize<2>,
      PageSize<3>,
      PageSize<4>,
      PageSize<5>,
    };

    template<int Level = 1, typename T>
    auto constexpr alignPageDown(T value) {
      return value & T{~(PageSize<Level> - 1)};
    }

    template<int Level = 1, typename T>
    auto constexpr alignPageUp(T value) {
      return alignPageDown<Level>(value + T{PageSize<Level> - 1});
    }

    VirtualAddress constexpr maxUaddr{1ull << pageOffsetBits<PageTableLevels + 1>};

    template<typename T>
    T makeCanonical(T ptr) {
      if(ptr & (T{maxUaddr} >> 1ull))
        return ptr | ~(T{maxUaddr} - T{1});
      else
        return ptr;
    }

    template<int level>
    union PageTableEntry;

    struct PageEntry;

    namespace PageTables {
      template<int level>
      struct PointedToT {
        using type = PageTableEntry<level - 1>;
      };

      template<>
      struct PointedToT<1> {
        using type = PageEntry;
      };

      template<int level>
      using PointedTo = typename PointedToT<level>::type;
    }

    union Permissions {
      Permissions(): rep{0} { }

      flo::Bitfield<1, 1> writeEnable;
      flo::Bitfield<2, 1> allowUserAccess;
      flo::Bitfield<3, 1> writethrough;
      flo::Bitfield<4, 1> disableCache;

      union {
        flo::Bitfield<8, 1> global;
        flo::Bitfield<63, 1> exectueDisable;
      } mapping;

      u64 rep;
    };

    template<int Level>
    union PageTableEntry {
      u64 rep;

      PageTableEntry(): rep{0} {}

      // Copying is _not_ OK, modifying a copy was a fun bug to track down :^)
      PageTableEntry(PageTableEntry const &other) = delete;

      // Assignment or moving is fine
      PageTableEntry(PageTableEntry      &&other): rep{other.rep} { }
      PageTableEntry &operator=(PageTableEntry const &other) { rep = other.rep; return *this; }
      PageTableEntry &operator=(PageTableEntry      &&other) { rep = other.rep; return *this; }

      flo::Bitfield<0, 1> present;
      flo::Bitfield<5, 1> accessed;
      flo::Bitfield<7, 1> isMappingBit; // Ignored if Level = 1

      Permissions perms;

      union {
        flo::Bitfield<8, 4> ignored;
        // Points to one page of another page table
        flo::Bitfield<pageOffsetBits<1>, maxPhysBits - pageOffsetBits<1>> physaddrPart;
      } pageTable;

      union {
        flo::Bitfield<6, 1> dirty;
        flo::Bitfield<8, 3> ignored;
        flo::Bitfield<pageOffsetBits<Level>, maxPhysBits - pageOffsetBits<Level>> physaddrPart;
      } mapping;

      bool isMapping() const {
        return Level == 1 || isMappingBit;
      }

      PhysicalAddress physaddr() const {
        auto l = [](auto &a) {
          return PhysicalAddress{a << a.startBit};
        };

        if(isMapping())
          return l(mapping.physaddrPart);
        else
          return l(pageTable.physaddrPart);
      }

      void setPhysaddr(PhysicalAddress addr) {
        auto l = [addr](auto &a) {
          a = addr.get() >> a.startBit;
        };

        if(isMapping())
          l(mapping.physaddrPart);
        else
          l(pageTable.physaddrPart);
      }

      constexpr static auto lvl = Level;

      auto *virtaddr() const {
        return getPhys<PageTables::PointedTo<Level>>(physaddr());
      }
    };

    // Page table entries should be 8 bytes/64 bits
    static_assert(sizeof(PageTableEntry<1>) == 8);
    static_assert(sizeof(PageTableEntry<2>) == 8);
    static_assert(sizeof(PageTableEntry<3>) == 8);
    static_assert(sizeof(PageTableEntry<4>) == 8);
    static_assert(sizeof(PageTableEntry<5>) == 8);

    template<int Level>
    union PageTable {
      std::array<PageTableEntry<Level>, PageTableSize> table;
      PageTable() {
        flo::Util::setmem((u8 *)&table, 0x00, sizeof(table));
      }
    };

    // All page tables should be a 4K page large
    static_assert(sizeof(PageTable<1>) == PageSize<1>);
    static_assert(sizeof(PageTable<2>) == PageSize<1>);
    static_assert(sizeof(PageTable<3>) == PageSize<1>);
    static_assert(sizeof(PageTable<4>) == PageSize<1>);
    static_assert(sizeof(PageTable<5>) == PageSize<1>);

    auto *getPagingRoot() {
      return getPhys<PageTable<PageTableLevels>>(flo::PhysicalAddress{flo::CPU::cr3});
    }

    namespace Impl {
      template<int Level>
      auto mapping(Permissions perms, PhysicalAddress addr) {
        PageTableEntry<Level> pte;
        pte.rep = perms.rep;
        pte.present = 1;
        pte.isMappingBit = 1;
        pte.setPhysaddr(addr);
        return pte;
      }

      template<int Level>
      auto table() {
        // Enforced permissions for page tables
        Permissions perms;
        perms.writeEnable = 1;
        perms.allowUserAccess = 0;
        perms.writethrough = 0;
        perms.disableCache = 0;

        PageTableEntry<Level> pte;
        pte.rep = perms.rep;
        pte.perms.mapping.global = 0;
        pte.present = 1;
        pte.isMappingBit = 0;
        return pte;
      }

      template<int Level>
      u64 getIndex(VirtualAddress addr) {
        return (addr >> pageOffsetBits<Level>) % VirtualAddress{PageTableSize};
      }
    }

    struct MappingError {
      enum {
        AlreadyMapped,
        NoAlignment,
      } type;

      PhysicalAddress phys;
      VirtualAddress virt;
      int level;

      union {
        struct {
          void *pageTableWithMapping;
          int mappingIndex;
        } alreadyMapped;
      };
    };

    template<int Level, typename Tracer>
    [[nodiscard]]
    std::optional<MappingError> map(PhysicalAddress phys, VirtualAddress virt, u64 &size, Permissions perms, PageTable<Level> &table, Tracer &&tracer) {
      auto ind = Impl::getIndex<Level>(virt);
      auto &currPTE = table.table[ind];

      auto trace = [&](auto ...vs) {
        tracer("[", Decimal{(u8)Level}, "]@", &table, "[", Decimal{(u16)ind}, "]: v", virt(), " ", std::forward<decltype(vs)>(vs)...);
      };

      MappingError err{};
      err.phys = phys;
      err.virt = virt;
      err.level = Level;
      if((Level == 1 || size >= PageSize<Level> - PageSize<Level - 1>) && // Don't map something which doesn't fill the lower level
         phys == alignPageDown<Level>(phys) &&
         virt == alignPageDown<Level>(virt)) {
        if(currPTE.present) {
          trace("Present mapping: ", currPTE.rep, " maps to ", currPTE.physaddr()());
          err.type = MappingError::AlreadyMapped;
          err.alreadyMapped.pageTableWithMapping = &table;
          err.alreadyMapped.mappingIndex = ind;
          return err;
        }
        //This gets a little noisy
        if constexpr(flo::Paging::noisy) {
          trace("Mapping!");
        }
        currPTE = Impl::mapping<Level>(perms, phys);
        if(size < PageSize<Level>)
          size = 0;
        else
          size -= PageSize<Level>;
      } else {
        if constexpr(Level == 1) {
          // We can't map this as the pointers aren't aligned
          err.type = MappingError::NoAlignment;
          return err;
        } else {
          PageTable<Level - 1> *nextTable;

          // Split the unaligned pointers up to the next level
          if(currPTE.present) {
            // Existing present entry
            if(currPTE.isMapping()) {
              // This is a mapping, bail out
              err.type = MappingError::AlreadyMapped;
              err.alreadyMapped.pageTableWithMapping = &table;
              err.alreadyMapped.mappingIndex = ind;
              return err;
            }
            else {
              // Get the existing table
              nextTable = getPhys<PageTable<Level - 1>>(currPTE.physaddr());
            }
            trace("Existing PT");
          }
          else {
            // Make a new page table, none is present
            auto pageTablePhys = getPhysicalPage(1);
            nextTable = new (getPhys<PageTable<Level - 1>>(pageTablePhys)) PageTable<Level - 1>();

            // Map this into the current table
            //trace("Next level table missing, mapping to ", nextTable);
            auto pte = Impl::table<Level>();
            pte.setPhysaddr(pageTablePhys);
            currPTE = pte;
            trace("New PT!");
          }

          constexpr auto step = PageSize<Level - 1>;

          while(size) {
            auto err = map<Level - 1>(phys, virt, size, perms, *nextTable, tracer);
            if(err)
              return err;

            if(ind++ == PageTableSize - 1)
              break;

            phys += static_cast<PhysicalAddress>(step);
            virt += static_cast<VirtualAddress>(step);
          }
        }
      }
      return std::nullopt;
    }

    template<typename Tracer>
    [[nodiscard]]
    auto map(PhysicalAddress phys, VirtualAddress virt, u64 size, Permissions perm, Tracer &&tracer) {
      while(1) {
        auto err = map(phys, virt, size, perm, *getPagingRoot(), tracer);
        if(err)
          return err;

        // Advance to the next top level page
        virt = alignPageUp<PageTableLevels>(virt + VirtualAddress {1ull});
        phys = alignPageUp<PageTableLevels>(phys + PhysicalAddress{1ull});

        if(!size)
          return err;
      }
    }

    [[nodiscard]]
    auto map(PhysicalAddress phys, VirtualAddress virt, u64 size, Permissions perm) {
      return map(phys, virt, size, perm, [](auto...) { });
    }

#define mapMacro(lvl)\
  {auto constexpr pageSz = PageSize<lvl>; \
  if(size >= pageSz && virt % VirtualAddress{pageSz} == VirtualAddress{0}){ /* Large enough and aligned */\
    PhysicalAddress page = getPhysicalPage(lvl);\
    if(page) {\
      auto err = map(page, virt, pageSz, perm);\
      if(err) return err;\
      virt += VirtualAddress{pageSz};\
      size -= pageSz;\
      continue;\
    }\
  }}

    [[nodiscard]]
    std::optional<MappingError> map(VirtualAddress virt, u64 size, Permissions perm) {
      // Size is aligned up to the next page size
      for(size = alignPageUp<1>(size); size;) {
        // At the time of writing this, you can't map anything above a level 3 page / 1GB :^(
        mapMacro(3);
        mapMacro(2);
        mapMacro(1);
        // This should be unreachable as running out of 1 level pages is a fatal error
      }

      return std::nullopt;
    }
#undef mapMacro

    template<bool reclaimPages, int Level>
    bool unmap(VirtualAddress &virt, u64 &size, PageTable<Level> &table) {
      constexpr auto stepSize = PageSize<Level>;

      bool left = false;
      auto it = std::begin(table.table);
      for(; it != std::end(table.table); ++ it) {
        auto &currPTE = *it;
        if(currPTE.present) {
          if(currPTE.isMapping()) {
            if constexpr(reclaimPages)
              returnPhysicalPage(currPTE.physaddr(), currPTE.lvl);
            currPTE.rep = 0;
          } else {
            if constexpr (Level != 1) {
              // Is table, recurse
              auto sizecpy = size;
              auto fullyUnmapped = unmap<reclaimPages>(virt, sizecpy, *getPhys<PageTable<Level - 1>>(currPTE.physaddr()));

              // Then unmap current level if no children are left
              if(fullyUnmapped) {
                returnPhysicalPage(currPTE.physaddr(), 1);
                currPTE.rep = 0;
              }
              else left = true;
            }
          }
        }
        if(size <= stepSize) {
          virt += VirtualAddress{size};
          size = 0;
          break;
        } else {
          virt += VirtualAddress{stepSize};
          size -= stepSize;
        }
      }

      if(left)
        return false;

      for(; it != std::end(table.table); ++it)
        if(it->present)
          return false;
      return true;
    }

    // Don't reclaim the pages if they're not supposed to get reused :^)
    template<bool reclaimPages>
    void unmap(VirtualAddress virt, u64 size) {
      struct CR3Resetter {
        ~CR3Resetter() { flo::CPU::cr3 = flo::CPU::cr3; }
      } reset;
      while(1) {
        unmap<reclaimPages>(virt, size, *getPagingRoot());

        if(!size)
          return;
      }
    }
  }

  template<typename Out, typename ErrorFunc>
  void checkMappingError(std::optional<Paging::MappingError> err, Out &&out, ErrorFunc &&errf) {
    if(err) {
      out("Error while mapping at paging level ", (u8)err->level);
      switch(err->type) {
        case flo::Paging::MappingError::AlreadyMapped:
          std::forward<Out>(out)("  Already mapped, ", "PT: ", err->alreadyMapped.pageTableWithMapping, ", ind = ", (u16)err->alreadyMapped.mappingIndex);
          break;
        case flo::Paging::MappingError::NoAlignment:
          std::forward<Out>(out)("  Misaligned pointers!");
          break;
        default:
          std::forward<Out>(out)("  Unknown error!");
          break;
      }

      std::forward<ErrorFunc>(errf)();
    }
  }

  template<typename PT, typename Tracer>
  void printPaging(PT &pt, Tracer &&tracer, u64 virtaddr = 0, u8 indent = 0) {
    bool visitedAny = false;
    for(int i = 0; i < flo::Paging::PageTableSize; ++ i) {
      auto &ent = pt.table[i];
      [[maybe_unused]]
      auto nextVirt = flo::Paging::makeCanonical(virtaddr | ((u64)i << flo::Paging::pageOffsetBits<ent.lvl>));
      if(!ent.present)
        continue;

      visitedAny = true;
      
      if(!ent.isMapping()) {
        tracer(spaces(indent), "Entry ", Decimal{i}, " v", nextVirt, " -> PT");

        if constexpr(ent.lvl < 2) {
          tracer(spaces(indent + 1), "Present level 1 mapping without mapping bit set!!");
          continue;
        }
        else {
          auto ptr = flo::getPhys<flo::Paging::PageTable<ent.lvl - 1>>(ent.physaddr());
          printPaging(*ptr, tracer, nextVirt, indent + 1);
        }
      }
      else if constexpr(flo::Paging::noisy) {
        tracer(spaces(indent), "Entry ", Decimal{i}, " v", nextVirt, " -> r", ent.perms.writeEnable ? "w" : "-", ent.perms.mapping.exectueDisable ? "-" : "x");
      }
    }
    if(!visitedAny) {
      tracer(spaces(indent), (uptr) &pt, ": This table was empty :(");
    }
  };
}

namespace flo {
#define consumeMacro(lvl) \
  {auto constexpr pageSz = flo::Paging::PageSize<lvl>;\
  if(size >= pageSz && addr % PhysicalAddress{pageSz} == PhysicalAddress{0}) { /* Is large enough, is page aligned */ \
    returnPhysicalPage(addr, lvl);\
    addr += PhysicalAddress{pageSz};\
    size -= pageSz;\
    continue;\
  }}

  void consumePhysicalMemory(PhysicalAddress addr, u64 size) {
    while(1) {
      consumeMacro(5);
      consumeMacro(4);
      consumeMacro(3);
      consumeMacro(2);
      consumeMacro(1);

      // Not large enough for any page, finish
      break;
    }
  }
#undef consumeMacro
}
