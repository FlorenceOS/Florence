#pragma once

#include "flo/Containers/Iterator.hpp"

#include "flo/Algorithm.hpp"
#include "flo/TypeTraits.hpp"
#include "flo/Util.hpp"

namespace flo {
  template<typename Storage, typename Compare = flo::Less<>>
  struct Sorted: Storage, Compare {
    constexpr Sorted(Compare cmp = Compare{}) : Compare{cmp} { }

    template<typename Ty>
    constexpr auto lowerBound(Ty const &val) const {
      return flo::lowerBound(container(), val, static_cast<Compare const &>(*this));
    }

    template<typename Ty>
    constexpr auto lowerBound(Ty const &val) {
      return flo::lowerBound(container(), val, static_cast<Compare const &>(*this));
    }

    template<typename Ty>
    constexpr auto upperBound(Ty const &val) const {
      return flo::upperBound(container(), val, static_cast<Compare const &>(*this));
    }

    template<typename Ty>
    constexpr auto upperBound(Ty const &val) {
      return flo::upperBound(container(), val, static_cast<Compare const &>(*this));
    }

    template<typename Ty>
    constexpr auto equalRange(Ty const &val) const {
      return flo::equalRange(container(), val, static_cast<Compare const &>(*this));
    }

    template<typename Ty>
    constexpr auto equalRange(Ty const &val) {
      return flo::equalRange(container(), val, static_cast<Compare const &>(*this));
    }

    template<typename... Ts>
    constexpr auto emplace(Ts &&... vs) {
      if constexpr(sizeof...(vs) == 1) {
        container().emplace(this->lowerBound(vs...), flo::forward<Ts>(vs)...);
      }
      else {
        decay<decltype(container().front())> value{flo::forward<Ts>(vs)...};
        container().emplace(this->lowerBound(value), flo::move(value));
      }
    }

    template<typename Ty>
    constexpr auto insert(Ty const &v) {
      return emplace(v);
    }

    template<typename Ty>
    constexpr auto find(Ty const &v) const {
      auto lb = this->lowerBound(v);
      if(lb != container().end() && *lb != v)
        return container().end();
      return lb;
    }

    template<typename Ty>
    constexpr bool contains(Ty const &v) const {
      return this->find(v) != container().end();
    }

    template<typename Ty>
    constexpr auto count(Ty const &v) const {
      auto [b, e] = equalRange(v);
      return flo::distance(b, e);
    }

  private:
    constexpr auto &container()       { return static_cast<Storage       &>(*this); }
    constexpr auto &container() const { return static_cast<Storage const &>(*this); }
  };
}
