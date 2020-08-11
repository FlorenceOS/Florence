#pragma once

#include "Ints.hpp"

#include "flo/Containers/Iterator.hpp"

namespace flo {
  template<typename T, uSz sz>
  struct Array {
    [[nodiscard]] constexpr T       *begin()       { return data_; }
    [[nodiscard]] constexpr T       *end()         { return data_ + sz; }

    [[nodiscard]] constexpr T const *begin() const { return data_; }
    [[nodiscard]] constexpr T const *end()   const { return data_ + sz; }

    [[nodiscard]] constexpr T const *cbegin() const { return data_; }
    [[nodiscard]] constexpr T const *cend()   const { return data_ + sz; }

    [[nodiscard]] constexpr auto rbegin()       { return makeReverseIterator(end()); }
    [[nodiscard]] constexpr auto rend()         { return makeReverseIterator(begin()); }

    [[nodiscard]] constexpr auto rbegin() const { return makeReverseIterator(end()); }
    [[nodiscard]] constexpr auto rend() const   { return makeReverseIterator(begin()); }

    [[nodiscard]] constexpr auto crbegin() const { return makeReverseIterator(cend()); }
    [[nodiscard]] constexpr auto crend()   const { return makeReverseIterator(cbegin()); }

    [[nodiscard]] constexpr T       *data()        { return data_; }
    [[nodiscard]] constexpr T const *data()  const { return data_; }

    [[nodiscard]] constexpr T       &operator[](uSz index)       { return data_[index]; };
    [[nodiscard]] constexpr T const &operator[](uSz index) const { return data_[index]; };

    [[nodiscard]] constexpr auto       &front()       { return *data_[0]; }
    [[nodiscard]] constexpr auto const &front() const { return *data_[0]; }

    [[nodiscard]] constexpr T       &back()       { return data_[sz - 1]; }
    [[nodiscard]] constexpr T const &back() const { return data_[sz - 1]; }

    [[nodiscard]] constexpr uSz size() const { return sz; }

    bool operator==(Array const &other) const {
      for(decltype(sz) i = 0; i < size(); ++ i)
        if(data_[i] != other[i])
          return false;
      return true;
    }

    T data_[sz];
  };
}
