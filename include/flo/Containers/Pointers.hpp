#pragma once

#include "Ints.hpp"

#include "flo/Util.hpp"

namespace flo {
  template<typename T>
  struct OwnPtr {
    OwnPtr() = default;
    // If one is destructed without deleting, hang
    ~OwnPtr() { while(1); }

    OwnPtr           (OwnPtr &&other) { ptr = flo::exchange(other.ptr, nullptr); }
    OwnPtr &operator=(OwnPtr &&other) { ptr = flo::exchange(other.ptr, nullptr); }

    OwnPtr           (OwnPtr const &) = delete;
    OwnPtr &operator=(OwnPtr const &) = delete;

    static OwnPtr adopt(T *ptr) {
      OwnPtr p;
      p.ptr = ptr;
      return p;
    }

    T *release() { return flo::exchange(ptr, nullptr); }
    T *get() const { return ptr; }

    void reset(T *p = nullptr) { ptr = p; }

    T *operator->() const { return ptr; }
    T &operator* () const { return *ptr; }
  private:
    T *ptr;
  };

  template<typename T>
  struct OwnPtr<T[]> {
    OwnPtr() = default;
    // If one is destructed without deleting, hang
    ~OwnPtr() { while(1); }

    OwnPtr           (OwnPtr &&other) { ptr = flo::exchange(other.ptr, nullptr); }
    OwnPtr &operator=(OwnPtr &&other) { ptr = flo::exchange(other.ptr, nullptr); }

    OwnPtr           (OwnPtr const &) = delete;
    OwnPtr &operator=(OwnPtr const &) = delete;

    static OwnPtr adopt(T *ptr) {
      OwnPtr p;
      p.ptr = ptr;
      return p;
    }

    T *release() { return flo::exchange(ptr, nullptr); }
    T *get() const { return ptr; }

    void reset(T *p = nullptr) { ptr = p; }

    T *operator->() const { return ptr; }
    T &operator* () const { return *ptr; }

    T &operator[](uSz ind) const { return ptr[ind]; }
  private:
    T *ptr;
  };
}
