#pragma once

#include "flo/Util.hpp"

namespace flo {
  struct nullopt_t { };
  inline nullopt_t nullopt;

  template<typename T>
  struct Optional {
    alignedStorage<sizeof(T), alignof(T)> storage;
    bool hasValue = false;

    template<typename ...ArgT>
    T &emplace(ArgT &&...args) {
      auto &ret = *new (storage.data) T(forward<ArgT>(args)...);
      hasValue = true;
      return ret;
    }

    void clear() {
      if (exchange(hasValue, false))
        get().~T();
    }

    Optional() = default;
    Optional(nullopt_t) { }
    Optional(Optional<T> &other) {
      hasValue = exchange(other.hasValue, false);
      if (hasValue)
        emplace(move(other.get()));
    }
    Optional(Optional<T> &&other) {
      hasValue = exchange(other.hasValue, false);
      if (hasValue)
        emplace(forward<T>(move(other).get()));
    }
    template<typename Ty>
    Optional(Ty &&val) {
      emplace(forward<Ty>(val));
    }
    ~Optional() {
      clear();
    }

    Optional &operator=(Optional const &other) {
      clear();
      emplace(other.get());
      return *this;
    }

    Optional &operator=(Optional &&other) {
      clear();
      hasValue = exchange(other.hasValue, false);
      if (hasValue)
        emplace(forward<T>(move(other).get()));
      return *this;
    }

    Optional &operator=(T const &other) {
      clear();
      emplace(other);
      return *this;
    }

    Optional &operator=(T &&other) {
      clear();
      emplace(forward(other));
      return *this;
    }

    operator bool() const { return hasValue; }

    T      &&get() &&      { return reinterpret_cast<T &&>(*storage.data); }
    T       &get() &       { return reinterpret_cast<T  &>(*storage.data); }
    T const &get() const & { return reinterpret_cast<T  &>(*storage.data); }

    auto &operator*()       { return get(); }
    auto &operator*() const { return get(); }

    auto operator->()       { return &get(); }
    auto operator->() const { return &get(); }
  };
}
