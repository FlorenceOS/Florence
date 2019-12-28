#pragma once

#include <array>
#include <memory>

#include "Ints.hpp"
#include "flo/Util.hpp"
#include "flo/Containers/Impl/VectorBase.hpp"

namespace flo {
  template<typename T, typename Alloc>
  struct DynamicVector: flo::VectorBase<DynamicVector<T, Alloc>, T, T *, uSz>, Alloc {
    friend struct flo::VectorBase<DynamicVector<T, Alloc>, T, T *, uSz>;
    ~DynamicVector() {
      for(auto &v: *this)
        v.~T();

      alloc().deallocate(storage.release(), storageSize);
    }
    // @TODO: = operators
    // @TODO: assign()

    using iterator = T *;
    using const_iterator = T const *;
    using reverse_iterator = std::reverse_iterator<T *>;
    using const_reverse_iterator = std::reverse_iterator<T const *>;

    using value_type = T;
    using size_type = uSz;
    using difference_type = iSz;
    using pointer = T *;
    using const_pointer = T const *;

    auto size() const { return numElements; }
    auto max_size() const { return Alloc::maxSize; }
    auto capacity() const { return storageSize; }
    auto shrink_to_fit() const {
      grow<EnableShrinking>(size(),
        []() { /* No realloc is a no-op */ },
        [this](auto newStorage, auto newCapacity) {
          // Move over elements to new storage
          itMoveConstuctDestroy(newStorage, this->begin(), this->end());
        }
      );
    }

    auto &swap(DynamicVector &other) {
      swap(numElements, other.numElements);
      swap(storage.elements, other.storage.elements);
      return *this;
    }

  protected:
    auto data_() const { return storage.get(); }

    struct EnableShrinking{};

    template<typename NoRealloc, typename Realloc, typename AllowShrink = void>
    auto grow(size_type newCapacity, NoRealloc &&noRealloc, Realloc &&realloc) {
      newCapacity = flo::Util::pow2Up(newCapacity);
      if(!std::is_same_v<AllowShrink, EnableShrinking> && newCapacity < capacity()) {
        std::forward<NoRealloc>(noRealloc)();
      }
      else {
        newCapacity = alloc().goodSize(newCapacity);

        if(newCapacity == storageSize)
          // Uhm... Sure.
          std::forward<NoRealloc>(noRealloc)();

        else {
          auto newStorage = alloc().allocate(newCapacity);
          std::forward<Realloc>(realloc)(newStorage, newCapacity);
          alloc().deallocate(storage.release(), storageSize);
          storage.reset(newStorage);
          storageSize = newCapacity;
        }
      }
    }

    auto adoptNewSize(size_type sz) { numElements = sz; }

  private:
    Alloc &alloc() { return static_cast<Alloc &>(*this); }

    uSz numElements = 0;
    uSz storageSize = 0;
    std::unique_ptr<T[]> storage;
  };
}
