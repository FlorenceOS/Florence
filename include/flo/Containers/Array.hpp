#pragma once

#include "Ints.hpp"

#include "flo/Containers/Impl/ContainerBase.hpp"

#include "flo/Containers/Iterator.hpp"

namespace flo {
  template<typename T, uSz sz>
  struct Array: ContainerBase<Array<T, sz>> {
    constexpr T       *begin()       { return data_; }
    constexpr T       *end()         { return data_ + sz; }

    constexpr T const *begin() const { return data_; }
    constexpr T const *end()   const { return data_ + sz; }

    constexpr T       *data()        { return data_; }
    constexpr T const *data()  const { return data_; }

    constexpr T       &operator[](uSz index)       { return data_[index]; };
    constexpr T const &operator[](uSz index) const { return data_[index]; };

    constexpr T       &back()       { return data_[sz - 1]; }
    constexpr T const &back() const { return data_[sz - 1]; }

    constexpr uSz size() const { return sz; }
    T data_[sz];
  };
}
