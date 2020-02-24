#include "flo/Algorithm.hpp"

#include "Testing.hpp"

TEST(LowerBound, SimpleCases) {
  {
    int arr[] {
      0, 1, 2, 3, 4, 5
    };

    EXPECT_EQ(flo::lowerBound(arr, flo::end(arr), 3), arr + 3);
  }
}

TEST(UpperBound, SimpleCases) {
  {
    int arr[] {
      0, 1, 2, 3, 4, 5
    };

    EXPECT_EQ(flo::upperBound(arr, flo::end(arr), 3), arr + 4);
  }
}

TEST(EqualRange, SimpleCases) {
  {
    int arr[] {
      0, 0, 1, 1, 1, 2, 3, 3, 3, 3, 4
    };

    {
      auto result = flo::equalRange(arr, flo::end(arr), 0);
      decltype(result) range{arr, arr + 2};
      EXPECT_EQ(result.begin, range.begin);
      EXPECT_EQ(result.end, range.end);
    }
  }
}

TEST(IsSorted, SimpleCases) {
  {
    int arr[] {
      0, 1, 2, 3, 4, 5, 6
    };
    EXPECT_TRUE(flo::isSorted(arr, flo::end(arr)));
  }
  {
    int arr[] {
      0, 1, 4, 3, 4, 5, 6
    };
    EXPECT_FALSE(flo::isSorted(arr, flo::end(arr)));
  }
}

TEST(Sort, RandomVectors) {
  Testing::runFor([]() {
    uSz elements[100];
    std::generate(elements, flo::end(elements), [](){ return Testing::rng(); });
    flo::sort(elements, flo::end(elements));
    EXPECT_TRUE(flo::isSorted(elements, flo::end(elements)));
    EXPECT_TRUE(std::is_sorted(elements, flo::end(elements)));
  });
}
