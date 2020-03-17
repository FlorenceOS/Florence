#pragma once

#include "flo/Containers/Array.hpp"

#include "flo/Paging.hpp"
#include "flo/Util.hpp"

namespace flo {
  namespace Memory {
    constexpr flo::Array<u64, 9> slabSizes {{}, {16, 24, 32, 64, 128, 256, 512, 1024, 2048}};

    // If you ask for size # of bytes, you will get goodSize(size) bytes.
    // So you might as well allocate that many if you have a growing container.
    constexpr uSz largeGoodSize(uSz size) {
      return Util::roundUp<flo::Paging::PageSize<1>>(size + 8) - 8;
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

  template<uSz size>
  void free_slab(void *);

  constexpr auto maxSlabSize = Memory::slabSizes.back();

  // Hey, you don't wanna worry about anything? Just the C API? Can't store the size? Like slow functions?
  // Don't wanna deal with non-canonical pointers? This is the API for you. It's simple,
  // straightforward and slow. Good on you for using this. Oh, did I mention it's slow?
  void *large_malloc(uSz size);

  // Free a pointer aquired through large_malloc
  void large_free(void *);

  template<uSz size>
  inline void *malloc() {
    if constexpr(size <= maxSlabSize)
      return malloc_slab<Memory::goodSize(size)>();
    else
      return large_malloc(size);
  }

  template<uSz size>
  inline void free(void *ptr) {
    if constexpr(size <= maxSlabSize)
      return free_slab<Memory::goodSize(size)>(ptr);
    else
      return large_free(ptr);
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
      return reinterpret_cast<T *>(large_malloc(sizeof(T) * numElements));
    }

    static void deallocate(T *ptr) {
      large_free(ptr);
    }

    static constexpr uSz goodSize(uSz numElements) {
      return Memory::largeGoodSize(numElements * sizeof(T))/sizeof(T);
    }
  };

  void *getVirtualPages(uSz numPages);
  void returnVirtualPages(void *at, uSz numPages);
}
