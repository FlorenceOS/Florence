#pragma once

#include "Ints.hpp"

#include "flo/Paging.hpp"
#include "flo/Util.hpp"

namespace flo {
  template<typename T>
  union OwnPtr {
    OwnPtr() = default;
    // If one is destructed without deleting, hang
    ~OwnPtr() { cleanup(); }

    OwnPtr           (OwnPtr &&other) {            ptr = flo::exchange(other.ptr, nullptr); }
    OwnPtr &operator=(OwnPtr &&other) { cleanup(); ptr = flo::exchange(other.ptr, nullptr); }

    OwnPtr           (OwnPtr const &) = delete;
    OwnPtr &operator=(OwnPtr const &) = delete;

    static OwnPtr adopt(T *ptr) {
      OwnPtr p;
      p.ptr = ptr;
      return p;
    }

    T *release() { return flo::exchange(ptr, nullptr); }
    T *get() const { return ptr; }

    void reset(T *p = nullptr) { cleanup(); ptr = p; }

    T *operator->() const { return ptr; }
    T &operator* () const { return *ptr; }

    void cleanup() {
      if(ptr)
        while(1){ }
    }
  private:
    T *ptr;
  };

  template<typename T>
  union OwnPtr<T[]> {
    OwnPtr() = default;
    // If one is destructed without deleting, hang
    ~OwnPtr() { cleanup(); }

    OwnPtr           (OwnPtr &&other) {            ptr = flo::exchange(other.ptr, nullptr); }
    OwnPtr &operator=(OwnPtr &&other) { cleanup(); ptr = flo::exchange(other.ptr, nullptr); }

    OwnPtr           (OwnPtr const &) = delete;
    OwnPtr &operator=(OwnPtr const &) = delete;

    static OwnPtr adopt(T *ptr) {
      OwnPtr p;
      p.ptr = ptr;
      return p;
    }

    T *release() { return flo::exchange(ptr, nullptr); }
    T *get() const { return ptr; }

    void reset(T *p = nullptr) { cleanup(); ptr = p; }

    T *operator->() const { return ptr; }
    T &operator* () const { return *ptr; }

    T &operator[](uSz ind) const { return ptr[ind]; }

    void cleanup() {
      if(ptr)
        while(1){ }
    }
  private:
    T *ptr;
  };
}
