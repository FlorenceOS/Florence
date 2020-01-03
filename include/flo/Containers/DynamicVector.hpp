#pragma once

#include "flo/Containers/SmallVector.hpp"

namespace flo {
  // The normal kind of vector from e.g. the standard library
  template<typename T, typename Alloc>
  using DynamicVector = flo::SmallVector<T, 0x0, Alloc>;
}
