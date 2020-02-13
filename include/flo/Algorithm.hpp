#pragma once

namespace flo {
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
