#pragma once

#include "Ints.hpp"

#include "flo/Containers/Array.hpp"
#include "flo/Containers/Optional.hpp"

#include "flo/Algorithm.hpp"
#include "flo/Bitfields.hpp"
#include "flo/CPU.hpp"
#include "flo/Florence.hpp"
#include "flo/Util.hpp"

namespace flo {
  namespace Paging {
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
      if((uptr)ptr & (maxUaddr() >> 1ull))
        return reinterpret_cast<T>((uptr)ptr | ~((maxUaddr()) - 1ull));
      else
        return reinterpret_cast<T>((uptr)ptr &  ((maxUaddr()) - 1ull));
    }

    template<>
    inline VirtualAddress makeCanonical<VirtualAddress>(VirtualAddress ptr) {
      if(ptr & (VirtualAddress{maxUaddr} >> 1ull))
        return ptr | ~(VirtualAddress{maxUaddr} - VirtualAddress{1});
      else
        return ptr & (VirtualAddress{maxUaddr} - VirtualAddress{1});
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
        flo::Bitfield<63, 1> executeDisable;
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

      constexpr static int lvl = Level;

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
      flo::Array<PageTableEntry<Level>, PageTableSize> table;
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

    inline auto *getPagingRoot() {
      return getPhys<PageTable<PageTableLevels>>(flo::PhysicalAddress{flo::CPU::cr3});
    }

    struct MappingError {
      enum {
        AlreadyMapped,
        NoAlignment,
      } type;

      PhysicalAddress phys;
      VirtualAddress virt;
      int level;
    };

    using oMappingError = flo::Optional<MappingError>;
    inline constexpr auto noMappingError = flo::nullopt;

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

      template<int Level, typename Conflicting, typename MakeMap, typename MapPred>
      oMappingError doMap(VirtualAddress &virt, u64 &size, PageTable<Level> &table, Conflicting &&conflicting, MakeMap &&makeMap, MapPred &&mapPred) {
        auto ind = Impl::getIndex<Level>(virt);
        
        for(; size && ind < PageTableSize; ++ind) {
          auto &pte = table.table[ind];

          [[maybe_unused]]
          auto step = [&]() {
            if(size < PageSize<Level>) {
              virt -= VirtualAddress{size};
              size = 0;
            }
            else {
              virt += VirtualAddress{PageSize<Level>};
              size -= PageSize<Level>;
            }
          };

          if(pte.present && pte.isMapping()) {
            // Tell the caller about the present mapping
            auto err = conflicting(virt, pte);
            if(err)
              return err;
          }

          if constexpr(Level > 1) {
            auto recurse = [&]() {
              return doMap(virt, size,
                *getPhys<PageTable<Level - 1>>(pte.physaddr()),
                conflicting, makeMap, mapPred
              );
            };

            // If there already was an entry here
            if(pte.present && !pte.isMapping()) { /* latter should always be true*/
              // If it's present, just recurse
              auto err = recurse();
              if(err)
                return err;

              continue;
            }

            if constexpr(Level < 4) {
              if(!pte.present && (virt & VirtualAddress{PageSize<Level> - 1})() == 0 && mapPred(virt, size, PageSize<Level>)) {
                // Make a mapping
                auto err = makeMap(virt, size, pte);
                if(err)
                  return err;

                step();
              }
            }

            if(!pte.present) {
              // We didn't create a mapping at this level in the last if, we make a PT and recurse!

              // Get a physical page for the table
              auto pageTablePhys = physFree.getPhysicalPage(1);

              // Construct page table
              new(getPhys<PageTable<Level - 1>>(pageTablePhys)) PageTable<Level - 1>();

              // Make a new PTE
              auto npte = Impl::table<Level>();
              npte.setPhysaddr(pageTablePhys);

              // Map this into the current PTE
              pte = npte;

              auto err = recurse();
              if(err)
                return err;

              continue;
            }
          }
          else {
            if(!pte.present) {
              // If this should lead to a mapping
              auto err = makeMap(virt, size, pte);
              if(err)
                return err;

              step();
            }
          }
        }

        return noMappingError;
      }
    }

    template<typename Tracer>
    [[nodiscard]]
    auto map(PhysicalAddress phys, VirtualAddress virt, u64 size, Permissions perm, Tracer &&tracer) {
      auto currPhys = [&](auto currVirt) {
        return phys + PhysicalAddress{currVirt() - virt()};
      };

      // Currently, any conflicting pages are just a straight up error.
      auto conflicting = [&](auto virtaddr, auto &pte) -> oMappingError {
        MappingError err{};
        err.phys = pte.physaddr();
        err.virt = virtaddr;
        err.level = decay<decltype(pte)>::lvl;

        err.type = MappingError::AlreadyMapped;
        return err;
      };

      // Calculate physical address to be mapped
      auto makeMap = [&](auto currVirt, auto csize, auto &pte) -> oMappingError {
        pte = Impl::mapping<decay<decltype(pte)>::lvl>(perm, currPhys(currVirt));
        return noMappingError;
      };
 
      // Make sure the physical address is aligned and that the page is not twice as big as our mapping
      auto mapPred = [&](auto currVirt, auto currSize, auto pageSize) -> bool {
        bool allow = (currPhys(currVirt)() & (pageSize - 1)) == 0 && pageSize < size * 2;
        return allow;
      };
      
      auto virtcpy = virt;
      return Impl::doMap(virtcpy, size, *getPagingRoot(), conflicting, makeMap, mapPred);
    }

    [[nodiscard]]
    inline auto map(PhysicalAddress phys, VirtualAddress virt, u64 size, Permissions perm) {
      return map(phys, virt, size, perm, [](auto...) { });
    }

    [[nodiscard]]
    inline oMappingError map(VirtualAddress virt, u64 size, Permissions perm) {
      size = alignPageUp<1>(size);

      // Currently, any conflicting pages are just a straight up error.
      auto conflicting = [&](auto virtaddr, auto &pte) -> oMappingError {
        MappingError err{};
        err.phys = pte.physaddr();
        err.virt = virtaddr;
        err.level = decay<decltype(pte)>::lvl;
        return err;
      };

      // Get physical page to be mapped
      auto makeMap = [&](auto currVirt, auto csize, auto &pte) -> oMappingError {
        if(auto ppage = physFree.getPhysicalPage(decay<decltype(pte)>::lvl); ppage)
          pte = Impl::mapping<decay<decltype(pte)>::lvl>(perm, ppage);
        return noMappingError;
      };

      // Make sure that the page is not twice as big
      auto mapPred = [&](auto currVirt, auto currSize, auto pageSize) -> bool {
        return pageSize/2 < currSize;
      };

      return Impl::doMap(virt, size, *getPagingRoot(), conflicting, makeMap, mapPred);
    }

    // Returns if the table should remain present (still has children)
    template<bool reclaimPages, int Level>
    bool unmap(VirtualAddress virt, u64 size, PageTable<Level> &table) {
      auto ind = Impl::getIndex<Level>(virt);

      bool left = anyOf(table.table.begin(), table.table.begin() + ind, [](auto &pte) { return pte.present; });

      [[maybe_unused]]
      auto step = [&]() {
        ++ind;
        if(size < PageSize<Level>) {
          virt -= VirtualAddress{size};
          size = 0;
        }
        else {
          virt += VirtualAddress{PageSize<Level>};
          size -= PageSize<Level>;
        }
      };
      
      for(; size && ind < PageTableSize; step()) {
        auto &pte = table.table[ind];

        if(pte.present && pte.isMapping()) {
          if constexpr(reclaimPages)
            physFree.returnPhysicalPage(pte.physaddr(), Level);
          pte.rep = 0;
          continue;
        }

        if constexpr(Level > 1) if(pte.present)
          if(unmap<reclaimPages>(virt, size, *getPhys<PageTable<Level - 1>>(pte.physaddr())))
            left = true;
      }

      return left || anyOf(table.table.begin() + ind, table.table.end(), [](auto &pte) { return pte.present; });
    }

    template<bool reclaimPages>
    void unmap(VirtualAddress virt, u64 size) {
      unmap<reclaimPages>(virt, size, *getPagingRoot());
    }
  }

  template<typename Out, typename ErrorFunc>
  void checkMappingError(flo::Paging::oMappingError err, Out &&out, ErrorFunc &&errf) {
    if(err) {
      out("Error while mapping ", err->virt(), " at paging level ", (u8)err->level);
      switch(err->type) {
      case flo::Paging::MappingError::AlreadyMapped:
        forward<Out>(out)("  Already mapped! ");
        break;
      case flo::Paging::MappingError::NoAlignment:
        forward<Out>(out)("  Misaligned pointers!");
        break;
      default:
        forward<Out>(out)("  Unknown error!");
        break;
      }

      forward<ErrorFunc>(errf)();
    }
  }

  template<int Level, typename Tracer>
  void printPaging(Paging::PageTable<Level> &pt, Tracer &&tracer, u64 virtaddr = 0, u8 indent = 0) {
    bool visitedAny = false;
    for(int i = 0; i < flo::Paging::PageTableSize; ++i) {
      auto &ent = pt.table[i];
      if(!ent.present)
        continue;

      [[maybe_unused]]
      auto nextVirt = flo::Paging::makeCanonical(virtaddr | ((u64)i << flo::Paging::pageOffsetBits<Level>));

      visitedAny = true;
      
      if(!ent.isMapping()) {
        tracer(spaces(indent), "Entry ", Decimal{i}, " v", nextVirt, " -> PT");

        if constexpr(Level < 2) {
          tracer(spaces(indent + 1), "Present level 1 mapping without mapping bit set!!");
          continue;
        }
        else {
          auto ptr = flo::getPhys<flo::Paging::PageTable<Level - 1>>(ent.physaddr());
          printPaging(*ptr, tracer, nextVirt, indent + 1);
        }
      }
      else
        tracer(spaces(indent), "Entry ", Decimal{i}, " v", nextVirt, " (r", ent.perms.writeEnable ? "w" : "-", ent.perms.mapping.executeDisable ? "-" : "x", ") -> p", ent.physaddr()());
    }
    if(!visitedAny)
      tracer(spaces(indent), &pt, ": This table was empty :(");
  };
}

namespace flo {
#define consumeMacro(lvl) \
  {auto constexpr pageSz = flo::Paging::PageSize<lvl>;\
  if(size >= pageSz && addr % PhysicalAddress{pageSz} == PhysicalAddress{0}) { /* Is large enough, is page aligned */ \
    physFree.returnPhysicalPage(addr, lvl);\
    addr += PhysicalAddress{pageSz};\
    size -= pageSz;\
    continue;\
  }}

  inline void consumePhysicalMemory(PhysicalAddress addr, u64 size) {
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
