#include "flo/Containers/Function.hpp"

#include "Testing.hpp"

int a() {
  return 4;
}

int b() {
  return 5;
}

TEST(Function, PlainFunctionPointer) {
  flo::Function<int()> f;
  f = a;
  ASSERT_EQ(f(), 4);
  f = b;
  ASSERT_EQ(f(), 5);
}

TEST(Function, FunctionWithState) {
  {
    auto l = [a = 5]() mutable { return a++; };

    auto f = flo::Function<int()>::make<Testing::DefaultAllocator>(l);
    ASSERT_EQ(f(), 5);
    ASSERT_EQ(f(), 6);
  }

  {
    int a = 5;
    auto l = [&]() mutable { return a++; };

    auto f = flo::Function<int()>::make<Testing::DefaultAllocator>(l);
    ASSERT_EQ(f(), 5);
    ASSERT_EQ(f(), 6);
    ASSERT_EQ(a, 7);
  }
}
