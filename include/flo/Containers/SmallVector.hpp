#pragma once

#include "Ints.hpp"

#include "flo/Containers/Impl/VectorBase.hpp"

#include "flo/Containers/Array.hpp"
#include "flo/Containers/Pointers.hpp"

#include "flo/TypeTraits.hpp"
#include "flo/Util.hpp"

namespace flo {
  // Small vector has a small inline capacity and doesn't allocate until it exceeds to extend it.
  // It's locality friendly and can grow as much as needed. Kind of a mix of StaticVector and DynamicVector
  template<typename T, uSz inlineSize, typename Alloc>
  struct SmallVector: flo::VectorBase<SmallVector<T, inlineSize, Alloc>, T, uSz> {
    friend struct flo::VectorBase<SmallVector<T, inlineSize, Alloc>, T, uSz>;
    ~SmallVector() {
      for(auto &v: *this)
        v.~T();

      if(!isInline())
        storage.outOfLine.reset();
    }
    // @TODO: = operators
    // @TODO: assign()

    using value_type = T;
    using InlineStorage = flo::Array<T, inlineSize>;
    using OutOfLineStorage = flo::OwnPtr<T[], Alloc>;
    using size_type = uSz;
    using difference_type = iSz;

    constexpr auto size() const { return numElements; }
    constexpr auto max_size() const { return Alloc::maxSize; }
    constexpr auto capacity() const { return storageSize; }

    constexpr bool isInline() const {
      return storageSize == storage.inOfLine.size();
    }

  protected:
    constexpr T *data_() {
      if(isInline())
        return storage.inOfLine.data();
      else
        return storage.outOfLine.get();
    }

    constexpr T const *data_() const {
      if(isInline())
        return storage.inOfLine.data();
      else
        return storage.outOfLine.get();
    }

    template<typename DoShrink, typename NoRealloc, typename Realloc>
    constexpr auto grow(size_type requestedCapacity, NoRealloc &&noRealloc, Realloc &&realloc) {
      if(flo::isSame<DoShrink, void> && requestedCapacity < capacity()) {
        flo::forward<NoRealloc>(noRealloc)();
        return;
      }

      if(requestedCapacity <= storage.inOfLine.size()) {
        if(isInline())
          flo::forward<NoRealloc>(noRealloc)();
        else {
          // Relocate out of line storage into inline
          auto oldStorage = std::move(storage.outOfLine);

          // From here on inline storage is active
          flo::forward<Realloc>(realloc)(storage.inOfLine.begin(), storage.inOfLine.size());
          makeInline();
        }
        return;
      }
      else {
        auto newCapacity = Alloc::goodSize(requestedCapacity);

        if(!flo::isSame<DoShrink, void> && newCapacity >= storageSize) { // Small optimization for shrinking
          flo::forward<NoRealloc>(noRealloc)();
          return;
        }

        else { // We have to allocate new memory
          auto newStorage = OutOfLineStorage::make(newCapacity);
          flo::forward<Realloc>(realloc)(newStorage.get(), newCapacity);

          if(!isInline())
            storage.outOfLine = std::move(newStorage);
          else
            new (&storage.outOfLine) OutOfLineStorage{std::move(newStorage)};

          storageSize = newCapacity;
        }
      }
    }

    constexpr auto adoptNewSize(size_type sz) { numElements = sz; }
    constexpr auto makeInline() { storageSize = storage.inOfLine.size(); }

  private:
    uSz numElements = 0;
    union U {
      U() { }
      ~U() { }
      OutOfLineStorage outOfLine;
      InlineStorage inOfLine;
    } storage;
    uSz storageSize = storage.inOfLine.size();
  };
}
