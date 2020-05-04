#pragma once

#include "flo/Containers/Array.hpp"

#include "flo/Paging.hpp"
#include "flo/Util.hpp"

namespace flo {
  namespace Memory {
    constexpr flo::Array<u64, 8> slabSizes {16, 32, 64, 128, 256, 512, 1024, 2048};

    // If you ask for size # of bytes, you will get goodSize(size) bytes.
    // So you might as well allocate that many if you have a growing container.
    constexpr uSz largeGoodSize(uSz size) {
      return Util::roundUp<flo::Paging::PageSize<1>>(size);
    }

    constexpr uSz goodSize(uSz size) {
      if(!size)
        return 0;

      for(auto &slabSz: slabSizes)
        if(size <= slabSz)
          return slabSz;

      return largeGoodSize(size);
    }
  }

  template<uSz size>
  void *malloc_slab();

  void *large_malloc_size(uSz size);

  template<uSz size>
  void free_slab(void *);

  void large_free_size(void *, uSz size);

  constexpr auto maxSlabSize = Memory::slabSizes.back();

  template<uSz size>
  inline void *malloc() {
    if constexpr(size <= maxSlabSize)
      return malloc_slab<Memory::goodSize(size)>();
    else
      return large_malloc_size(size);
  }

  inline const flo::Array<void *(*)(), Memory::slabSizes.size()> malloc_funcs {
    malloc<Memory::slabSizes[0]>,
    malloc<Memory::slabSizes[1]>,
    malloc<Memory::slabSizes[2]>,
    malloc<Memory::slabSizes[3]>,
    malloc<Memory::slabSizes[4]>,
    malloc<Memory::slabSizes[5]>,
    malloc<Memory::slabSizes[6]>,
    malloc<Memory::slabSizes[7]>,
  };

  // You have to free() with the same size.
  inline void *malloc_size(uSz sz) {
    for(uSz i = 0; i < Memory::slabSizes.size(); ++ i)
      if(sz <= Memory::slabSizes[i])
        return malloc_funcs[i]();

    return large_malloc_size(sz);
  }

  inline void *malloc(uSz size) {
    size = Memory::goodSize(size + 8);
    auto base = (u64 *)malloc_size(size);
    *base = size;
    return base + 1;
  }

  inline void *malloc_eternal(uSz sz) {
    return malloc_size(sz);
  }

  template<uSz size>
  inline void free(void *ptr) {
    if constexpr(size <= maxSlabSize)
      return free_slab<Memory::goodSize(size)>(ptr);
    else
      return large_free_size(ptr, size);
  }

  inline const flo::Array<void (*)(void *), Memory::slabSizes.size()> free_funcs {
    free<Memory::slabSizes[0]>,
    free<Memory::slabSizes[1]>,
    free<Memory::slabSizes[2]>,
    free<Memory::slabSizes[3]>,
    free<Memory::slabSizes[4]>,
    free<Memory::slabSizes[5]>,
    free<Memory::slabSizes[6]>,
    free<Memory::slabSizes[7]>,
  };

  // Free something aquired from malloc_size
  inline void free_size(void *ptr, uSz sz) {
    for(uSz i = 0; i < Memory::slabSizes.size(); ++ i)
      if(sz <= Memory::slabSizes[i])
        return free_funcs[i](ptr);

    return large_free_size(ptr, sz);
  }

  inline void free(void *ptr) {
    auto pp = (u64 *)ptr;
    auto sz = pp[-1];
    return free_size(&pp[-1], sz);
  }

  template<typename T>
  struct Allocator {
    static T *allocate() {
      return reinterpret_cast<T *>(malloc<sizeof(T)>());
    }

    static void deallocate(T *ptr) {
      free<sizeof(T)>(ptr);
    }
  };

  template<typename T>
  struct Allocator<T[]> {
    static T *allocate(uSz numElements) {
      return reinterpret_cast<T *>(malloc(sizeof(T) * numElements));
    }

    static void deallocate(T *ptr) {
      free(ptr);
    }

    static constexpr uSz goodSize(uSz numElements) {
      return Memory::goodSize(numElements * sizeof(T))/sizeof(T);
    }
  };

  template<typename T>
  struct SizedAllocator: Allocator<T> {
    SizedAllocator() { }

    template<typename otherT>
    SizedAllocator(SizedAllocator<otherT> &&other): allocatedSize{other.allocatedSize} { }

    T *allocate() {
      allocatedSize = sizeof(T);
      return (T *)malloc<sizeof(T)>();
    }

    void deallocate(T *ptr) {
      return free_size(ptr, allocatedSize);
    }

    uSz allocatedSize;
  };

  void *getVirtualPages(uSz numPages);
  void returnVirtualPages(void *at, uSz numPages);

  struct WriteBack {};
  struct WriteCombining {};

  flo::VirtualAddress mapMMIO(flo::PhysicalAddress addr, uSz size, WriteBack);
  flo::VirtualAddress mapMMIO(flo::PhysicalAddress addr, uSz size, WriteCombining);
  void freeMapMMIO(flo::VirtualAddress addr, uSz size);

  // Allocate uncached memory for use with MMIO
  // Returns both virtual and physical addresses

  // Same as above functions but makes a physical
  // page instead of taking an existing range
  struct VirtPhysPair {
    flo::VirtualAddress virt;
    flo::PhysicalAddress phys;
  };

  VirtPhysPair allocMMIO(uSz size, WriteBack);
  VirtPhysPair allocMMIO(uSz size, WriteCombining);
  void freeAllocMMIO(void *virt);
}
