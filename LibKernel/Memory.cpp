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
      kernelRW.readable = 1;
      kernelRW.writeable = 1;
      kernelRW.executable = 1;
      kernelRW.userspace = 0;
      kernelRW.cacheable = 1;
      kernelRW.writethrough = 0;
      kernelRW.global = 0;

      flo::Paging::map({
        .virt = pageBase,
        .size = numPages * flo::Paging::PageSize<1>,
        .perm = kernelRW,
      });

      return pageBase;
    }

    union Stack {
      Stack *next;
      struct {
        u8 data[4096 - 16];
        u8 stackBase[16]{};
      };
    };

    auto mmioPerms() {
      flo::Paging::Permissions result;

      result.readable = 1;
      result.writeable = 1;
      result.executable = 0;
      result.userspace = 0;
      result.cacheable = 0;
      result.global = 0;

      return result;
    }


    auto doMapMMIO(flo::PhysicalAddress phys, uSz size, flo::Paging::Permissions perms) {
      size = flo::Paging::align_page_up<1>(size);
      auto virt = flo::VirtualAddress{(u64)getVirtualPages(size/flo::Paging::PageSize<1>)};

      flo::Paging::map_phys({
        .phys = phys,
        .virt = virt,
        .size = size,
        .perm = perms
      });

      return virt;
    }
  }
}

void *flo::getVirtualPages(uSz numPages) {
  return (void *)flo::Memory::pageRanges.get(numPages * flo::Paging::PageSize<1>, flo::random);
}

void flo::returnVirtualPages(void *at, uSz numPages) {
  flo::Memory::pageRanges.add((u64)at, numPages * flo::Paging::PageSize<1>);
}

void *flo::large_malloc_size(uSz size) {
  auto numPages = flo::Paging::align_page_up<1>(size);
  auto base = flo::Memory::makePages(numPages);
  return flo::getVirt<void>(base);
}

void flo::large_free_size(void *ptr, uSz size) {
  auto numPages = flo::Paging::align_page_up<1>(size);
  flo::Paging::unmap({
    .virt = VirtualAddress{(u64)ptr},
    .size = numPages * flo::Paging::PageSize<1>,
    .recycle_pages = true,
  });
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

flo::VirtualAddress flo::mapMMIO(flo::PhysicalAddress addr, uSz size, WriteBack) {
  auto perms = flo::Memory::mmioPerms();
  perms.writethrough = 1;
  return flo::Memory::doMapMMIO(addr, size, perms);
}

flo::VirtualAddress flo::mapMMIO(flo::PhysicalAddress addr, uSz size, WriteCombining) {
  auto perms = flo::Memory::mmioPerms();
  perms.writethrough = 0;
  return flo::Memory::doMapMMIO(addr, size, perms);
}

void flo::freeMapMMIO(flo::VirtualAddress virt, uSz size) {
  flo::Paging::unmap({
    .virt = virt,
    .size = flo::Paging::align_page_up<1>(size),
    .recycle_pages = false,
  });
}

flo::VirtPhysPair flo::allocMMIO(uSz size, WriteBack tag) {
  assert(size <= flo::Paging::PageSize<1>);
  flo::VirtPhysPair result{};
  result.phys = flo::physFree.getPhysicalPage(1);
  result.virt = flo::mapMMIO(result.phys, size, tag);
  return result;
}

flo::VirtPhysPair flo::allocMMIO(uSz size, WriteCombining tag) {
  assert(size <= flo::Paging::PageSize<1>);
  flo::VirtPhysPair result{};
  result.phys = flo::physFree.getPhysicalPage(1);
  result.virt = flo::mapMMIO(result.phys, size, tag);
  return result;
}

void flo::freeAllocMMIO(void *virt) {
  flo::Paging::unmap({
    .virt = VirtualAddress{(u64)virt},
    .size = flo::Paging::PageSize<1>,
    .recycle_pages = true,
  });
}

namespace {
  flo::Memory::Stack *stack_head = nullptr;
}

extern "C"
void *makeStack() {
  flo::Memory::Stack *stack;
  if(stack_head) {
    stack = flo::exchange(stack_head, stack_head->next);
  }
  else {
    stack = flo::Allocator<flo::Memory::Stack>::allocate();
  }

  flo::Util::setmem(stack->stackBase, 0, sizeof(stack->stackBase));
  return stack->stackBase;
}

extern "C"
void freeStack(void *ptr) {
  auto stack = (flo::Memory::Stack *)ptr;
  stack->next = stack_head;
  stack_head = stack;
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

namespace flo::Memory {
  namespace {
    template<int level>
    bool __attribute__((always_inline)) consume_page(flo::PhysicalAddress &addr, u64 &size) {
      auto constexpr pageSz = flo::Paging::PageSize<level>;
      if(size >= pageSz && addr() % pageSz == 0) {
        //flo::Memory::pline("Consuming physical page ", addr(), " at level ", level);
        flo::physFree.returnPhysicalPage(addr, level);
        size -= pageSz;
        addr += PhysicalAddress{pageSz};
        return true;
      }
      return false;
    }
  }
}

void flo::consumePhysicalMemory(flo::PhysicalAddress addr, u64 size) {
  using flo::Memory::consume_page;

  flo::Memory::pline("Consuming physical memory ", addr(), " to ", addr() + size);

  while(
    consume_page<5>(addr, size) ||
    consume_page<4>(addr, size) ||
    consume_page<3>(addr, size) ||
    consume_page<2>(addr, size) ||
    consume_page<1>(addr, size)
  );
}
