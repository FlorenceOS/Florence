#include "flo/Containers/RangeRandomizer.hpp"

#include "Testing.hpp"

template<uSz alignment>
void rangeTest(uSz rangeSize, uSz requestedSize, uSz expectedSlides) {
  typename flo::RangeRandomizer<alignment>::Range r{0, rangeSize};
  r.recalc(requestedSize);
  if(expectedSlides != r.possibleSlides) {
    std::cerr
      << "Expected possible slides " << expectedSlides
      << " but got " << r.possibleSlides
      << " slides with range size " << rangeSize
      << ", requesting " << requestedSize
      << " and alignment " << alignment
      << "\n";
    ADD_FAILURE();
  }
}

TEST(RangeRandomizer_Range, possibleSlides) {
  rangeTest<4096>(4096, 4096, 1);
  rangeTest<4096>(4096 * 2 - 1, 4096, 1);
  rangeTest<4096>(4096 * 2, 4096, 2);

  rangeTest<4096>(4096, 1, 1);

  rangeTest<8>(4096, 8, 512);
}

TEST(RangeRandomizer_Range, split) {
  {
    typename flo::RangeRandomizer<1>::Range r{16, 16};

    int firstRuns = 0;
    int secondRuns = 0;

    r.split(1, 1, [&](auto &&first) {
      ++firstRuns;
      EXPECT_EQ(first.base, 16);
      EXPECT_EQ(first.size, 1);
    }, [&](auto &&second) {
      ++secondRuns;
      EXPECT_EQ(second.base, 18);
      EXPECT_EQ(second.size, 14);
    });

    EXPECT_EQ(firstRuns, 1);
    EXPECT_EQ(secondRuns, 1);
  }

  {
    typename flo::RangeRandomizer<1>::Range r{16, 16};

    int firstRuns = 0;
    int secondRuns = 0;

    r.split(0, 1, [&](auto &&first) {
      ++firstRuns;
    }, [&](auto &&second) {
      ++secondRuns;
      EXPECT_EQ(second.base, 17);
      EXPECT_EQ(second.size, 15);
    });

    EXPECT_EQ(firstRuns, 0);
    EXPECT_EQ(secondRuns, 1);
  }

  {
    typename flo::RangeRandomizer<1>::Range r{16, 16};

    int firstRuns = 0;
    int secondRuns = 0;

    r.split(15, 1, [&](auto &&first) {
      ++firstRuns;
      EXPECT_EQ(first.base, 16);
      EXPECT_EQ(first.size, 15);
    }, [&](auto &&second) {
      ++secondRuns;
    });

    EXPECT_EQ(firstRuns, 1);
    EXPECT_EQ(secondRuns, 0);
  }

  {
    typename flo::RangeRandomizer<1>::Range r{16, 16};

    int firstRuns = 0;
    int secondRuns = 0;

    r.split(14, 1, [&](auto &&first) {
      ++firstRuns;
      EXPECT_EQ(first.base, 16);
      EXPECT_EQ(first.size, 14);
    }, [&](auto &&second) {
      ++secondRuns;
      EXPECT_EQ(second.base, 31);
      EXPECT_EQ(second.size, 1);
    });

    EXPECT_EQ(firstRuns, 1);
    EXPECT_EQ(secondRuns, 1);
  }
}

TEST(RangeRandomizer, SimpleCases) {
  flo::RangeRandomizer<8> rnd;
  rnd.add(16, 4096);

  bool gotValue[4096]{};

  auto numResults = 0;
  Testing::runFor([&]() {
    auto val = rnd.get(8, Testing::rng);
    if(val) {
      val -= 16;
      EXPECT_LT(val, 4096);
      EXPECT_EQ(val % 8, 0);
      EXPECT_EQ(flo::exchange(gotValue[val], true), false);
      ++numResults;
    }
  });

  EXPECT_EQ(numResults, 512);
}
