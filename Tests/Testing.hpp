#pragma once

#include <random>
#include <chrono>

#include "Ints.hpp"

namespace Testing {
  inline static std::mt19937_64 rng(std::chrono::system_clock::now().time_since_epoch().count());

  inline static auto urand(uSz maxVal = std::numeric_limits<uSz>::max()) {
    return std::uniform_int_distribution<uSz>(0, maxVal)(rng);
  }

  template<typename F>
  inline static void forRandomInt(F &&f, std::chrono::duration<double> runFor = std::chrono::seconds(1)) {
    auto start = std::chrono::steady_clock::now();
    while(std::chrono::steady_clock::now() - start < runFor) {
      f(urand());
    }
  }

  template<typename T>
  struct DefaultAllocator: std::allocator<T> {
    constexpr static auto goodSize(uSz least) {
      return least;
    }

    constexpr static auto maxSize = 1ull << 38;
  };
}

#include "gtest/gtest.h"
#include "gmock/gmock.h"

using testing::Contains;
using testing::ElementsAre;
using testing::ElementsAreArray;
