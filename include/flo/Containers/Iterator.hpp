#pragma once

#include "Ints.hpp"

namespace flo {
  template<typename BaseIt>
  struct ReverseIterator {
    BaseIt it;

    ReverseIterator &operator++()   { --it; return *this; }
    ReverseIterator operator++(int) { ReverseIterator copy = *this; --it; return copy; }
    ReverseIterator &operator--()   { ++it; return *this; }
    ReverseIterator operator--(int) { ReverseIterator copy = *this; ++it; return copy; }

    auto &operator*() const { return *it; }

    bool operator==(ReverseIterator const &other) const { return it == other.it; }
    bool operator!=(ReverseIterator const &other) const { return it != other.it; }

    ReverseIterator &operator+=(iSz diff) { it -= diff; return *this; }
    ReverseIterator &operator-=(iSz diff) { it += diff; return *this; }

    ReverseIterator operator+(iSz diff) { ReverseIterator copy = *this; copy += diff; return copy; }
    ReverseIterator operator-(iSz diff) { ReverseIterator copy = *this; copy -= diff; return copy; }

    auto operator-(ReverseIterator const &other) { return other.it - it; }

    BaseIt base() const { return it; }
  };

  template<typename BaseIt>
  ReverseIterator(BaseIt) -> ReverseIterator<BaseIt>;

  template<typename Iterator>
  inline auto makeReverseIterator(Iterator it) {
    return ReverseIterator{it - 1};
  }

  template<typename Iterator>
  inline auto makeReverseIterator(ReverseIterator<Iterator> it) {
    return it.base() + 1;
  }

  template<typename Iterator>
  inline auto distance(Iterator a, Iterator b) {
    return b - a;
  }
}
