#pragma once

#include <functional>
#include <cmath> // No idea why this has to be included, compiler freaks out if it isn't.

namespace flo {
  template<typename Storage>
  struct Unsorted: Storage {
    using Storage::Storage;

    template<typename Ty>
    auto find(Ty const &v) const {
      return std::find(this->begin(), this->end(), v);
    }

    template<typename Ty>
    bool contains(Ty const &v) const {
      return this->find(v) != this->end();
    }

    template<typename Ty, typename Compare = std::equal_to<>>
    auto count(Ty const &v, Compare comp = {}) const {
      return std::count_if(this->begin(), this->end(), [&comp, &v](auto const &e) { return comp(v, e); });
    }
  };
}
