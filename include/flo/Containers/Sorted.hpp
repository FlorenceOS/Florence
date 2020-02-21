#pragma once

#include "flo/Containers/Iterator.hpp"

#include "flo/Algorithm.hpp"
#include "flo/TypeTraits.hpp"
#include "flo/Util.hpp"

namespace flo {
  template<typename Storage, typename Compare = std::less<>>
  struct Sorted: Storage, Compare {
      Sorted(Compare cmp = Compare{}): Compare{cmp} { }

      template<typename Ty>
      auto lowerBound(Ty const &val) const {
        return std::lower_bound(this->begin(), this->end(), val, static_cast<Compare const &>(*this));
      }

      template<typename Ty>
      auto upperBound(Ty const &val) const {
        return std::upper_bound(this->begin(), this->end(), val, static_cast<Compare const &>(*this));
      }

      template<typename Ty>
      auto equalRange(Ty const &val) const {
        return std::equal_range(this->begin(), this->end(), val, static_cast<Compare const &>(*this));
      }

      template<typename Beg, typename End>
      auto merge(Beg beg, End end) {
        auto num = std::distance(beg, end);
        static_cast<Storage &>(*this).insert(this->end(), beg, end);
        std::inplace_merge(this->begin(), this->end() - num, this->end());
      }

      template<typename ...Ts>
      auto emplace(Ts &&...vs) {
        this->emplace_back(std::forward<Ts>(vs)...);
        std::inplace_merge(this->begin(), this->end() - 1, this->end());
      }

      template<typename Ty>
      auto insert(Ty const &v) {
        return emplace(v);
      }

      template<typename Ty>
      auto find(Ty const &v) const {
        auto lb = this->lowerBound(v);
        if(lb != this->end() && *lb != v)
          return this->end();
        return lb;
      }

      template<typename Ty>
      bool contains(Ty const &v) const {
        return this->find(v) != this->end();
      }

      template<typename Ty>
      auto count(Ty const &v) const {
        auto [b, e] = equalRange(v);
        return std::distance(b, e);
      }
  };
}
