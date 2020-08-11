#pragma once

#include "Ints.hpp"

#include "flo/Util.hpp"
#include "flo/Containers/Array.hpp"

namespace flo {
  template<uSz size>
  struct Bitset {
    bool isSet(uSz index) const {
      return (data[index/8] >> (index % 8)) & 1;
    }

    bool isUnset(uSz index) const {
      return !isSet(index);
    }

    void set(uSz index) {
      data[index/8] |= (1 << (index % 8));
    }

    void unset(uSz index) {
      data[index/8] &= ~(1 << (index % 8));
    }

    bool operator[](uSz index) const {
      return isSet(index);
    }

    uSz firstUnset() const {
      for(uSz i = 0; i < size; ++ i)
        if(isUnset(i))
          return i;

      return (uSz)-1;
    }

    uSz firstSet() const {
      for(uSz i = 0; i < size; ++ i)
        if(isSet(i))
          return i;

      return (uSz)-1;
    }
  private:
    flo::Array<u8, flo::Util::roundUp<8>(size)> data{{}};
  };
}
