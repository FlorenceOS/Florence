#pragma once

#include "flo/Algorithm.hpp"

namespace flo {
  template<typename Storage>
  struct Unsorted: Storage {
    using Storage::Storage;

    template<typename Ty>
    auto find(Ty const &v) const {
      return flo::find(this->begin(), this->end(), v);
    }

    template<typename Ty>
    bool contains(Ty const &v) const {
      return this->find(v) != this->end();
    }

    template<typename Ty, typename Compare = flo::Equal<>>
    auto count(Ty const &v, Compare comp = {}) const {
      return flo::countIf(this->begin(), this->end(), [&comp, &v](auto const &e) { return comp(v, e); });
    }
  };
}
