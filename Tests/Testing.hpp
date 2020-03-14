#pragma once

#include "Ints.hpp"

#include "gmock/gmock.h"
#include "gtest/gtest.h"

#include <chrono>
#include <random>

namespace Testing {
  inline static std::mt19937_64 rng(std::chrono::system_clock::now().time_since_epoch().count());

  inline static auto urand(uSz maxVal = std::numeric_limits<uSz>::max()) {
    return std::uniform_int_distribution<uSz>(0, maxVal)(rng);
  }

  template<typename F>
  void runFor(F &&f, std::chrono::duration<double> duration = std::chrono::seconds(1)) {
    auto start = std::chrono::steady_clock::now();
    while(std::chrono::steady_clock::now() - start < duration && !testing::Test::HasFailure())
      f();
  }

  template<typename F>
  inline static void forRandomInt(F &&f, std::chrono::duration<double> duration = std::chrono::seconds(1)) {
    runFor([&]() {
      f(urand());
    }, duration);
  }

  template<typename T>
<<<<<<< Updated upstream
  struct DefaultAllocator: std::allocator<T> {
    constexpr static auto goodSize(uSz least) {
      return least;
    }

    constexpr static auto maxSize = 1ull << 38;
=======
  struct DefaultAllocator {
    static T *allocate() {
      return reinterpret_cast<T *>(malloc(sizeof(T)));
    }

    static void deallocate(T *ptr) {
      return free(ptr);
    }
  };

  template<typename T>
  struct DefaultAllocator<T[]> {
    static T *allocate(uSz num) {
      if(!num)
        return nullptr;
      return reinterpret_cast<T *>(malloc(sizeof(T) * num));
    }

    static void deallocate(T *ptr) {
      return free(ptr);
    }

    static constexpr auto goodSize(uSz least) {
      return least;
    }
>>>>>>> Stashed changes
  };
}

using testing::Contains;
using testing::ElementsAre;
using testing::ElementsAreArray;
