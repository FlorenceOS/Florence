#pragma once

#include <array>
#include <memory>

#include "Ints.hpp"
#include "flo/Util.hpp"
#include "flo/Containers/Impl/VectorBase.hpp"

namespace flo {
  // Small vector has a small inline capacity and doesn't allocate until it exceeds to extend it.
  // It's locality friendly and can grow as much as needed. Kind of a mix of StaticVector and DynamicVector
  template<typename T, uSz inlineSize, typename Alloc>
  struct SmallVector: flo::VectorBase<SmallVector<T, inlineSize, Alloc>, T, uSz>, Alloc {
    friend struct flo::VectorBase<SmallVector<T, inlineSize, Alloc>, T, uSz>;
    ~SmallVector() {
      for(auto &v: *this)
        v.~T();

      if(!isInline())
        alloc().deallocate(storage.outOfLine.release(), storageSize);
    }
    // @TODO: = operators
    // @TODO: assign()

    using value_type = T;
    using InlineStorage = std::array<T, inlineSize>;
    using OutOfLineStorage = std::unique_ptr<T[]>;
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
      if(std::is_same_v<DoShrink, void> && requestedCapacity < capacity()) {
        std::forward<NoRealloc>(noRealloc)();
        return;
      }

      if(requestedCapacity <= storage.inOfLine.size()) {
        if(isInline())
          std::forward<NoRealloc>(noRealloc)();
        else {
          // Relocate out of line storage into inline
          auto oldStorage = storage.outOfLine.release();

          // From here on inline storage is active
          std::forward<Realloc>(realloc)(storage.inOfLine.begin(), storage.inOfLine.size());
          alloc().deallocate(oldStorage, storageSize);
          makeInline();
        }
        return;
      }
      else {
        auto newCapacity = alloc().goodSize(flo::Util::pow2Up(requestedCapacity));

        if(!std::is_same_v<DoShrink, void> && newCapacity >= storageSize) { // Small optimization for shrinking
          std::forward<NoRealloc>(noRealloc)();
          return;
        }

        else { // We have to allocate new memory
          auto newStorage = alloc().allocate(newCapacity);
          std::forward<Realloc>(realloc)(newStorage, newCapacity);
          if(!isInline()) {
            alloc().deallocate(storage.outOfLine.release(), storageSize);
            storage.outOfLine.reset(newStorage);
          }
          else {
            new (&storage.outOfLine) OutOfLineStorage(newStorage);
          }
          storageSize = newCapacity;
        }
      }
    }

    constexpr auto adoptNewSize(size_type sz) { numElements = sz; }
    constexpr auto makeInline() { storageSize = storage.inOfLine.size(); }

  private:
    constexpr Alloc &alloc() { return static_cast<Alloc &>(*this); }

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
