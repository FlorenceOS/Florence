#pragma once

#include "Ints.hpp"

#include "flo/Containers/Iterator.hpp"

#include "flo/TypeTraits.hpp"

namespace flo {
  template<typename T = void>
  struct Less {
    constexpr bool operator()(T const &lhs, T const &rhs) const { return lhs < rhs; }
  };

  template<>
  struct Less<void> {
    template<typename Lhs, typename Rhs>
    constexpr bool operator()(Lhs const &lhs, Rhs const &rhs) const { return lhs < rhs; }
  };

  template<typename T = void>
  struct Greater {
    constexpr bool operator()(T const &lhs, T const &rhs) const { return lhs > rhs; }
  };

  template<>
  struct Greater<void> {
    template<typename Lhs, typename Rhs>
    constexpr bool operator()(Lhs const &lhs, Rhs const &rhs) const { return lhs > rhs; }
  };

  template<typename T = void>
  struct Equal {
    constexpr bool operator()(T const &lhs, T const &rhs) const { return lhs == rhs; }
  };

  template<>
  struct Equal<void> {
    template<typename Lhs, typename Rhs>
    constexpr bool operator()(Lhs const &lhs, Rhs const &rhs) const { return lhs == rhs; }
  };

  template<typename Beg, typename End, typename F>
  constexpr bool allOf(Beg beg, End end, F &&f) {
    while(beg != end) if(!f(*beg++))
      return false;
    return true;
  }

  template<typename Beg, typename End>
  constexpr bool allOf(Beg beg, End end) {
    while(beg != end) if(!*beg++)
      return false;
    return true;
  }

  template<typename Beg, typename End, typename F>
  constexpr bool anyOf(Beg beg, End end, F &&f) {
    while(beg != end) if(f(*beg++))
      return true;
    return false;
  }

  template<typename Beg, typename End>
  constexpr bool anyOf(Beg beg, End end) {
    while(beg != end) if(*beg++)
      return true;
    return false;
  }

  template<typename Beg, typename End, typename F>
  constexpr void forEach(Beg beg, End end, F &&f) {
    while(beg != end)
      f(*beg++);
  }

  template<typename Lhs, typename Rhs>
  constexpr auto max(Lhs lhs, Rhs rhs) {
    if(lhs < rhs)
      return rhs;
    return lhs;
  }

  template<typename Lhs, typename Rhs>
  constexpr auto min(Lhs lhs, Rhs rhs) {
    if(lhs < rhs)
      return lhs;
    return rhs;
  }

  template<typename Value, typename Iterator>
  constexpr Iterator find(Iterator begin, Iterator end, Value const &v) {
    for(; begin != end; ++begin)
      if(*begin == v)
        return begin;

    return begin;
  }

  template<typename T>
  constexpr void swap(T &lhs, T &rhs) {
    auto temp = lhs;
    lhs = rhs;
    rhs = temp;
  }

  template<typename T> constexpr auto begin(T &&container) { return container.begin(); }
  template<typename T> constexpr auto end(T &&container)   { return container.end(); }

  template<typename T, uSz size>
  constexpr auto begin(T (&arr)[size]) { return arr; }
  template<typename T, uSz size>
  constexpr auto end(T (&arr)[size])   { return arr + size; }

  template<typename LBeg, typename LEnd, typename Rhs>
  constexpr auto equals(LBeg lbeg, LEnd lend, Rhs rhs) {
    while(lbeg != lend)
      if(*lbeg++ != *rhs++)
        return false;
    return true;
  }

  template<typename Container, typename Iter>
  constexpr auto equals(Container &&cont, Iter it) {
    return equals(begin(cont), end(cont), it);
  }
}
