#pragma once

#include "Ints.hpp"

#include "flo/Memory.hpp"
#include "flo/Paging.hpp"
#include "flo/Util.hpp"

namespace flo {
  namespace Impl {
    template<typename T, typename Allocator, typename Derived>
    struct OwnPtrBase: Allocator {
      OwnPtrBase(Allocator alloc = Allocator{})
        : Allocator{alloc}
        { }
      ~OwnPtrBase() { cleanup(); }

      OwnPtrBase(OwnPtrBase &&other)
        : Allocator{flo::move(other.alloc())}
        {
        ptr = flo::exchange(other.ptr, nullptr);
      }

      OwnPtrBase(T *ptr, Allocator alloc = Allocator{})
        : Allocator{flo::move(alloc)}
        , ptr{ptr}
        { }

      OwnPtrBase &operator=(OwnPtrBase &&other) {
        cleanup();
        alloc() = flo::move(other.alloc());
        ptr = flo::exchange(other.ptr, nullptr);
        return *this;
      }

      OwnPtrBase           (OwnPtrBase const &) = delete;
      OwnPtrBase &operator=(OwnPtrBase const &) = delete;

      [[nodiscard]]
      static Derived adopt(T *ptr, Allocator alloc = Allocator{}) {
        return Derived{OwnPtrBase{ptr, flo::move(alloc)}};
      }

      [[nodiscard]]
      T *release() { return flo::exchange(ptr, nullptr); }

      [[nodiscard]]
      T *get() const { return ptr; }

      void reset(T *p = nullptr) { cleanup(); ptr = p; }

      [[nodiscard]] Allocator &alloc() { return static_cast<Allocator &>(*this); }

    protected:
      T *ptr = nullptr;

      void cleanup() {
        if(ptr)
          alloc().deallocate(ptr);
      }
    };
  }

  template<typename T, typename Allocator>
  struct OwnPtr: Impl::OwnPtrBase<T, Allocator, OwnPtr<T, Allocator>> {
    template<typename ...Ts>
    static OwnPtr make(Ts &&...vs) {
      Allocator alloc{};
      auto ptr{OwnPtr::adopt(alloc.allocate(), flo::move(alloc))};
      new (ptr.get()) T(flo::forward<Ts>(vs)...);
      return ptr;
    }

    template<typename ...Ts>
    static OwnPtr make(Allocator alloc, Ts &&...vs) {
      auto ptr{OwnPtr::adopt(alloc.allocate())};
      new (ptr.get()) T(flo::forward<Ts>(vs)...);
      return ptr;
    }

    T *operator->() const { return this->get(); }
    T &operator* () const { return *this->get(); }

    uSz goodSize(uSz numElements) const {
      return Allocator::goodSize(numElements);
    }
  };

  template<typename T, typename Allocator>
  struct OwnPtr<T[], Allocator>: Impl::OwnPtrBase<T, Allocator, OwnPtr<T[], Allocator>> {
    static OwnPtr make(uSz numElements, Allocator alloc = Allocator{}) {
      return OwnPtr::adopt(alloc.allocate(numElements), flo::move(alloc));
    }

    T &operator[](uSz ind) const { return this->get()[ind]; }
  };
}
