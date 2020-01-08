#include "Testing.hpp"
#include "flo/Util.hpp"

TEST(Util, populationCount) {
  EXPECT_EQ(flo::Util::populationCount(0), 0);
  EXPECT_EQ(flo::Util::populationCount(1), 1);
  EXPECT_EQ(flo::Util::populationCount(2), 1);
  EXPECT_EQ(flo::Util::populationCount(3), 2);
  EXPECT_EQ(flo::Util::populationCount(4), 1);
  EXPECT_EQ(flo::Util::populationCount(5), 2);
  EXPECT_EQ(flo::Util::populationCount(6), 2);
  EXPECT_EQ(flo::Util::populationCount(7), 3);

  EXPECT_EQ(flo::Util::populationCount(0ll << 40), 0);
  EXPECT_EQ(flo::Util::populationCount(1ll << 40), 1);
  EXPECT_EQ(flo::Util::populationCount(2ll << 40), 1);
  EXPECT_EQ(flo::Util::populationCount(3ll << 40), 2);
  EXPECT_EQ(flo::Util::populationCount(4ll << 40), 1);
  EXPECT_EQ(flo::Util::populationCount(5ll << 40), 2);
  EXPECT_EQ(flo::Util::populationCount(6ll << 40), 2);
  EXPECT_EQ(flo::Util::populationCount(7ll << 40), 3);

  Testing::forRandomInt([](auto val) {
    EXPECT_EQ(flo::Util::populationCount(val), __builtin_popcountll(val));
  });
}

TEST(Util, unsetCount) {
  Testing::forRandomInt([](auto val) {
    EXPECT_EQ(flo::Util::unsetCount(val), 64 - __builtin_popcountll(val));
  });
}

TEST(Util, pow2Up) {
  EXPECT_EQ(flo::Util::pow2Up(0), 1);
  EXPECT_EQ(flo::Util::pow2Up(1), 1);
  EXPECT_EQ(flo::Util::pow2Up(2), 2);
  EXPECT_EQ(flo::Util::pow2Up(3), 4);
  EXPECT_EQ(flo::Util::pow2Up(4), 4);
  EXPECT_EQ(flo::Util::pow2Up(5), 8);
}

TEST(Util, pow2Down) {
  EXPECT_EQ(flo::Util::pow2Down(0), 1);
  EXPECT_EQ(flo::Util::pow2Down(1), 1);
  EXPECT_EQ(flo::Util::pow2Down(2), 2);
  EXPECT_EQ(flo::Util::pow2Down(3), 2);
  EXPECT_EQ(flo::Util::pow2Down(4), 4);
  EXPECT_EQ(flo::Util::pow2Down(5), 4);
}

TEST(Util, isPow2) {
  EXPECT_EQ(flo::Util::isPow2(1), true);
  EXPECT_EQ(flo::Util::isPow2(2), true);
  EXPECT_EQ(flo::Util::isPow2(3), false);
  EXPECT_EQ(flo::Util::isPow2(4), true);
  EXPECT_EQ(flo::Util::isPow2(5), false);
}

TEST(Util, roundUp) {
  EXPECT_EQ(flo::Util::roundUp<5>(0), 0);
  EXPECT_EQ(flo::Util::roundUp<5>(1), 5);
  EXPECT_EQ(flo::Util::roundUp<5>(2), 5);
  EXPECT_EQ(flo::Util::roundUp<5>(3), 5);
  EXPECT_EQ(flo::Util::roundUp<5>(4), 5);
  EXPECT_EQ(flo::Util::roundUp<5>(5), 5);
}

TEST(Util, roundDown) {
  EXPECT_EQ(flo::Util::roundDown<5>(0), 0);
  EXPECT_EQ(flo::Util::roundDown<5>(1), 0);
  EXPECT_EQ(flo::Util::roundDown<5>(2), 0);
  EXPECT_EQ(flo::Util::roundDown<5>(3), 0);
  EXPECT_EQ(flo::Util::roundDown<5>(4), 0);
  EXPECT_EQ(flo::Util::roundDown<5>(5), 5);
}

TEST(Util, msb) {
  EXPECT_EQ(flo::Util::msb(0), 0);
  EXPECT_EQ(flo::Util::msb(1), 1);
  EXPECT_EQ(flo::Util::msb(2), 2);
  EXPECT_EQ(flo::Util::msb(3), 2);
  EXPECT_EQ(flo::Util::msb(4), 4);
  EXPECT_EQ(flo::Util::msb(5), 4);
}

TEST(Util, lsb) {
  EXPECT_EQ(flo::Util::lsb(0), 0);
  EXPECT_EQ(flo::Util::lsb(1), 1);
  EXPECT_EQ(flo::Util::lsb(2), 2);
  EXPECT_EQ(flo::Util::lsb(3), 1);
  EXPECT_EQ(flo::Util::lsb(4), 4);
  EXPECT_EQ(flo::Util::lsb(5), 1);
}

TEST(Util, genMagic) {
  EXPECT_EQ(flo::Util::genMagic("ABCDEFGH"),
       ((u64)'A'
     | ((u64)'B' << 8)
     | ((u64)'C' << 16)
     | ((u64)'D' << 24)
     | ((u64)'E' << 32)
     | ((u64)'F' << 40)
     | ((u64)'G' << 48)
     | ((u64)'H' << 56)
  ));
}
