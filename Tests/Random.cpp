#include "Testing.hpp"

#include "flo/Random.hpp"

#include <random>

TEST(UniformInts, NeverAbove) {
  Testing::forRandomInt([](uSz maxVal) {
    flo::UniformInts<u64> dist(0, maxVal);
    EXPECT_LE(dist(Testing::rng), maxVal);
  });
}

TEST(UniformInts, NeverBelow) {
  Testing::forRandomInt([](uSz minVal) {
    flo::UniformInts<u64> dist(minVal, flo::Limits<u64>::max);
    EXPECT_GE(dist(Testing::rng), minVal);
  });
}
