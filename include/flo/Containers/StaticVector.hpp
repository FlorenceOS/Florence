#pragma once

#include "Ints.hpp"

#include "flo/Containers/Impl/VectorBase.hpp"
#include "flo/Containers/Array.hpp"

namespace flo {
  // Setting doDestructor to false makes the StaticVector destructor a no-op.
  // It still calls the destructor on its elements when calling erase() et al.
  // This makes the StaticVector usable as a global variable with permanent lifetime.
  template<typename T, auto cap, bool doDestructor = true>
  struct StaticVector: flo::VectorBase<StaticVector<T, cap, doDestructor>, T, decltype(cap)> {
    friend struct flo::VectorBase<StaticVector<T, cap, doDestructor>, T, decltype(cap)>;
    ~StaticVector() {
      if constexpr(doDestructor)
        for(auto &v: *this)
          v.~T();
    }
    // @TODO: = operators
    // @TODO: assign()

    using Storage = Array<T, cap>;

    using value_type = T;
    using size_type = decltype(cap);
    using difference_type = iSz;

    constexpr auto size() const { return numElements; }
    constexpr auto max_size() const { return cap; }
    constexpr auto capacity() const { return cap; }

    constexpr bool isInline() const {
      return true;
    }

  protected:
    constexpr T       *data_()       { return storage.elements.data(); }
    constexpr T const *data_() const { return storage.elements.data(); }

    template<typename DoShrink, typename NoRealloc, typename Realloc>
    constexpr auto grow(size_type requestedCapacity, NoRealloc &&noRealloc, Realloc &&realloc) const {
      forward<NoRealloc>(noRealloc)();
    }

    constexpr auto adoptNewSize(size_type sz) { numElements = sz; }

  private:
    decltype(cap) numElements = 0;
    union U { Storage elements; ~U() {}; U() {}; } storage;
  };
}
