#include "flo/Memory.hpp"

#include "flo/Containers/RangeRandomizer.hpp"

#include "flo/Assert.hpp"
#include "flo/IO.hpp"
#include "flo/Paging.hpp"
#include "flo/Random.hpp"

namespace flo::Memory {
  namespace {
    constexpr bool quiet = true;
    auto pline = flo::makePline<quiet>("[MEMORY]");

    flo::RangeRandomizer<flo::Paging::PageSize<1>> pageRanges;

    flo::VirtualAddress makePages(uSz numPages) {
      auto pageBase = flo::VirtualAddress{(u64)getVirtualPages(numPages)};

      assert(pageBase);

      flo::Paging::Permissions kernelRW;
      kernelRW.writeEnable = 1;
      kernelRW.allowUserAccess = 0;
      kernelRW.writethrough = 0;
      kernelRW.disableCache = 0;
      kernelRW.mapping.global = 0;
      kernelRW.mapping.executeDisable = 1;

      // @TODO: lock mapping
      auto err = flo::Paging::map(pageBase, numPages * flo::Paging::PageSize<1>, kernelRW);
      flo::checkMappingError(err, flo::Memory::pline, []() {
        assert_not_reached();
      });

      return pageBase;
    }

    struct Stack {
      u8 data[4096 - 16];
      u8 stackBase[16]{};
    };
  }
}

void *flo::getVirtualPages(uSz numPages) {
  return (void *)flo::Memory::pageRanges.get(numPages * flo::Paging::PageSize<1>, flo::random);
}

void flo::returnVirtualPages(void *at, uSz numPages) {
  flo::Memory::pageRanges.add((u64)at, numPages * flo::Paging::PageSize<1>);
}

void *flo::large_malloc_size(uSz size) {
  auto numPages = flo::Paging::alignPageUp<1>(size);
  auto base = flo::Memory::makePages(numPages);
  return flo::getVirt<void>(base);
}

void flo::large_free_size(void *ptr, uSz size) {
  auto numPages = flo::Paging::alignPageUp<1>(size);
  flo::Paging::unmap<true>(VirtualAddress{(u64)ptr}, numPages * flo::Paging::PageSize<1>);
  flo::returnVirtualPages(ptr, numPages);
}

template<uSz size>
struct MallocSlab {
  static_assert(size >= sizeof(void *));
  static_assert(flo::Paging::PageSize<1> % size == 0);

  struct FreeEntry {
    FreeEntry *next;
  };

  // @TODO: lock this structure
  inline static FreeEntry *next = nullptr;

  static void deallocate(void *slab) {
    auto freeSlab = reinterpret_cast<FreeEntry *>(slab);
    freeSlab->next = next;
    next = freeSlab;
  }

  static void *allocate() {
    flo::Memory::pline("Checking freelist for slab of size ", size);
    
    if(next)
      return flo::exchange(next, next->next);

    flo::Memory::pline("No slab in freelist.");

    auto base = flo::Memory::makePages(1);

    flo::Memory::pline("Made new memory at ", base());

    // Put other slabs in freelist
    for(uSz slab = 1; slab * size < flo::Paging::PageSize<1>; ++slab)
      deallocate((void *)(base() + slab * size));

    flo::Memory::pline("Unused new memory added to freelist");

    // Return slab 0
    return flo::getVirt<void>(base);
  }
};

template<uSz size>
void *flo::malloc_slab() {
  return MallocSlab<size>::allocate();
}

template<uSz size>
void flo::free_slab(void *ptr) {
  return MallocSlab<size>::deallocate(ptr);
}

extern "C"
void *makeStack() {
  auto stack = flo::Allocator<flo::Memory::Stack>::allocate();
  flo::Util::setmem(stack->stackBase, 0, sizeof(stack->stackBase));
  return stack->stackBase;
}

extern "C"
void freeStack(void *ptr) {
  auto stack = (flo::Memory::Stack *)((uptr)ptr & ~0xFFFull);
  flo::Allocator<flo::Memory::Stack>::deallocate(stack);
}

// Instatiate all the malloc/free functions for the slab sizes
template<uSz ind = 0>
struct Dummy {
  static void dummy() {
    if constexpr(ind < flo::Memory::slabSizes.size()) {
      constexpr auto slabSize = flo::Memory::slabSizes[ind];
      flo::free_slab<slabSize>(flo::malloc_slab<slabSize>());
      Dummy<ind + 1>::dummy();
    }
  }
};

Dummy d;
