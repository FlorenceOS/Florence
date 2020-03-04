#pragma once

#include "flo/Paging.hpp"
#include "flo/Util.hpp"

namespace flo {
  namespace Memory {
    // If you ask for size # of bytes, you will get goodSize(size) bytes.
    // So you might as well allocate that many if you have a growing container.
    constexpr uSz goodSize(uSz size) {
      if(!size)
        return 0;

      /*if(size <= 16)
        return 16;
      if(size <= 25)
        return 25;
      if(size <= 41)
        return 41;
      if(size <= 67)
        return 67;
      if(size <= 109)
        return 109;
      if(size <= 177)
        return 177;
      if(size <= 287)
        return 287;
      if(size <= 464)
        return 464;
      if(size <= 751)
        return 751;
      if(size <= 1216)
        return 1216;
      if(size <= 1967)
        return 1967;
      if(size <= 3184)
        return 3184;
      if(size <= 5151)
        return 5151;
      if(size <= 8336)
        return 8336;*/

      return Util::roundUp<flo::Paging::PageSize<1>>(size + 8) - 8;
    }
  }

  /*template<uSz size>
  void *malloc_slab();

  // Fast slabs
  extern void *malloc_slab<16>();
  extern void *malloc_slab<25>();
  extern void *malloc_slab<41>();
  extern void *malloc_slab<67>();
  extern void *malloc_slab<109>();
  extern void *malloc_slab<177>();
  extern void *malloc_slab<287>();
  extern void *malloc_slab<464>();
  extern void *malloc_slab<751>();
  extern void *malloc_slab<1216>();
  extern void *malloc_slab<1967>();
  extern void *malloc_slab<3184>();
  extern void *malloc_slab<5151>();
  extern void *malloc_slab<8336>();

  constexpr auto maxSlabSize = 8336ULL;*/

  // Hey, you don't wanna worry about anything? Just the C API? Can't store the size? Like slow functions?
  // Don't wanna deal with non-canonical pointers? This is the API for you. It's simple,
  // straightforward and slow. Good on you for using this. Oh, did I mention it's slow?
  void *large_malloc(uSz size);

  /*template<uSz size>
  [[always_inline]]
  inline void *malloc() {
    if constexpr(size <= maxSlabSize)
      return malloc_slab<goodSize(size)>();

    return large_malloc(size);
  }

  template<typename T>
  T *mallocate() {
    reinterpret_cast<T *>(malloc<sizeof(T)>());
  }

  template<typename T>
  T *mallocate(uSz num) {
    reinterpret_cast<T *>(malloc(num * sizeof(T)));
  }*/

  // Free a pointer aquired through large_malloc
  void large_free(void *);

  /*void free(void *, uSz size);

  template<typename T>
  struct DefaultAllocator {
    T *allocate() const {
      return mallocate<T>();
    }

    void deallocate() const {
      return freeate<T>();
    }

    constexpr static uSz goodSize(uSz size) const {
      return flo::Memory::goodSize(size);
    }
  };*/

  void *getVirtualPages(uSz numPages);
  void returnVirtualPages(void *at, uSz numPages);
}
