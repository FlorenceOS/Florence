#pragma once

#include <random>
#include <chrono>

#include "Ints.hpp"

namespace Testing {
  inline static std::mt19937_64 rng(std::chrono::system_clock::now().time_since_epoch().count());

  template<typename F>
  inline static void forRandomInt(F &&f) {
    for(int i = 0; i < 1000; ++ i) {
      f(Testing::rng());
    }
  }

  inline static auto urand(uSz maxVal = std::numeric_limits<uSz>::max()) {
    return std::uniform_int_distribution<uSz>(0, maxVal)(rng);
  }

  template<typename T>
  struct DefaultAllocator: std::allocator<T> {
    constexpr auto goodSize(uSz least) const {
      return least;
    }
  };
}

#include "gtest/gtest.h"
#include "gmock/gmock.h"

using testing::Contains;
using testing::ElementsAre;
using testing::ElementsAreArray;
