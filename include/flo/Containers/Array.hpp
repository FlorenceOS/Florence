#pragma once

#include "Ints.hpp"
#include "flo/Containers/Iterator.hpp"
#include "flo/Containers/Impl/ContainerBase.hpp"

namespace flo {
  template<typename T, uSz sz>
  struct Array: ContainerBase<Array<T, sz>> {
    T       *begin()       { return data_; }
    T       *end()         { return data_ + sz; }

    T const *begin() const { return data_; }
    T const *end()   const { return data_ + sz; }

    T       *data()        { return data_; }
    T const *data()  const { return data_; }

    T       &operator[](uSz index)       { return data_[index]; };
    T const &operator[](uSz index) const { return data_[index]; };
  private:
    T data_[sz];
  };
}
