#pragma once

#include <array>

#include "Ints.hpp"

#include "flo/Containers/Impl/VectorBase.hpp"

namespace flo {
  // Setting doDestructor to false makes the StaticVector destructor a no-op.
  // It still calls the destructor on its elements when calling erase() et al.
  // This makes the StaticVector usable as a global variable with permanent lifetime.
  template<typename T, auto cap, bool doDestructor = true>
  struct StaticVector: flo::VectorBase<StaticVector<T, cap, doDestructor>, T, T *, decltype(cap)> {
    friend struct flo::VectorBase<StaticVector<T, cap, doDestructor>, T, T *, decltype(cap)>;
    ~StaticVector() {
      if constexpr(doDestructor)
        for(auto &v: *this)
          v.~T();
    }
    // @TODO: = operators
    // @TODO: assign()

    using Storage = std::array<T, cap>;

    using iterator = T *;
    using const_iterator = T const *;
    using reverse_iterator = std::reverse_iterator<T *>;
    using const_reverse_iterator = std::reverse_iterator<T const *>;

    using value_type = T;
    using size_type = decltype(cap);
    using difference_type = iSz;
    using pointer = T *;
    using const_pointer = T const *;

    constexpr auto size() const { return numElements; }
    constexpr auto max_size() const { return cap; }
    constexpr auto capacity() const { return cap; }
    constexpr auto shrink_to_fit() const { }

    constexpr auto &swap(StaticVector &other) {
      swap(numElements, other.numElements);
      swap(storage.elements, other.storage.elements);
      return *this;
    }

  protected:
    constexpr T       *data_()       { return storage.elements.data(); }
    constexpr T const *data_() const { return storage.elements.data(); }

    template<typename NoRealloc, typename Realloc>
    constexpr auto grow(size_type new_capacity, NoRealloc &&noRealloc, Realloc &&realloc) const {
      std::forward<NoRealloc>(noRealloc)();
    }

    constexpr auto adoptNewSize(size_type sz) { numElements = sz; }

  private:
    decltype(cap) numElements = 0;
    union U { Storage elements; ~U() {}; U() {}; } storage;
  };
}
