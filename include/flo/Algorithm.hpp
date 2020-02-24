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

  template<typename Iterator, typename Predicate>
  constexpr auto countIf(Iterator begin, Iterator end, Predicate &&pred) {
    uSz result = 0;

    for(; begin != end; ++begin)
      if(pred(*begin))
        ++result;

    return result;
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

  template<typename Iterator, typename Value, typename Compare = flo::Less<>>
  constexpr Iterator lowerBound(Iterator begin, Iterator end, Value const &value, Compare cmp = Compare{}) {
    while(begin != end) {
      auto count = flo::distance(begin, end);
      auto mid = flo::next(begin, count/2);
      if(cmp(*mid, value))
        begin = flo::next(mid, 1);
      else
        end = mid;
    }
    return begin;
  }

  template<typename Container, typename Value, typename Compare = flo::Less<>>
  constexpr auto lowerBound(Container &&cont, Value const &value, Compare cmp = Compare{}) {
    return lowerBound(begin(cont), end(cont), value, cmp);
  }

  template<typename Iterator, typename Value, typename Compare = flo::Less<>>
  constexpr Iterator upperBound(Iterator begin, Iterator end, Value const &value, Compare cmp = Compare{}) {
    while(begin != end) {
      auto count = flo::distance(begin, end);
      auto mid = flo::next(begin, count/2);
      if(!cmp(value, *mid))
        begin = flo::next(mid, 1);
      else
        end = mid;
    }
    return begin;
  }

  template<typename Container, typename Value, typename Compare = flo::Less<>>
  constexpr auto upperBound(Container &&cont, Value const &value, Compare cmp = Compare{}) {
    return upperBound(begin(cont), end(cont), value, cmp);
  }

  template<typename Iterator, typename Value, typename Compare = flo::Less<>>
  constexpr auto equalRange(Iterator begin, Iterator end, Value const &value, Compare cmp = Compare{}) {
    struct {
      Iterator begin{};
      Iterator end{};
    } result;

    result.begin = begin;
    result.end = end;

    return [&result, &value, &cmp]() mutable {
      auto &[begin, end] = result;

      // Optimization instead of just returning lowerBound(), upperBound().
      // Check if they're both in the same half
      while(begin != end) {
        auto count = flo::distance(begin, end);
        auto mid = flo::next(begin, count/2);

        // If *mid < value, equalRange has to be within the second half
        if(cmp(*mid, value))
          begin = flo::next(mid, 1);

        // If value < *mid, equalRange has to be within the first half
        else if(cmp(value, *mid))
          end = mid;

        // If value == *mid, we have to split into upper and lower bound
        else {
          begin = lowerBound(begin, mid, value, cmp);
          end = upperBound(mid + 1, end, value, cmp);
          break;
        }
      }

      return result;
    }();
  }

  template<typename Container, typename Value, typename Compare = flo::Less<>>
  constexpr auto equalRange(Container &&cont, Value const &value, Compare cmp = Compare{}) {
    return equalRange(begin(cont), end(cont), value, cmp);
  }
  }

  template<typename Iterator, typename Predicate>
  constexpr Iterator partition(Iterator begin, Iterator end, Predicate pred) {
    for(auto it = begin + 1; it != end; ++it) if(pred(*it))
      swap(*it, *begin++);
    return begin;
  }

  template<typename Iterator, typename Compare = flo::Less<>>
  constexpr void insertionSort(Iterator begin, Iterator end, Compare cmp = Compare{}) {
    while(begin != end) {
      auto smallest = begin;
      for(auto it = begin + 1; it != end; ++it) if(cmp(*it, *smallest))
        smallest = it;
      swap(*begin++, *smallest);
    }
  }

  template<typename Iterator, typename Compare = flo::Less<>>
  constexpr bool isSorted(Iterator begin, Iterator end, Compare cmp = Compare{}) {
    if(begin != end) {
      auto next = begin + 1;
      while(next != end) {
        if(cmp(*next, *begin))
          return false;

        begin = next++;
      }
    }

    return true;
  }
}
