#include "flo/Containers/SmallVector.hpp"

#include "Testing.hpp"
#include "VectorTests.hpp"

template<typename T, uSz inlineSize, typename Alloc>
void SmallVectorInvariant(flo::SmallVector<T, inlineSize, Alloc> &v) {
  auto isStoredInline = [](decltype(v) &vec) {
    return (u8 *)&vec <= (u8 *)vec.data() && (u8 *)vec.data() < (u8 *)&vec + sizeof(vec);
  };

  EXPECT_EQ(v.isInline(), isStoredInline(v));
  EXPECT_EQ(v.isInline(), v.capacity() == inlineSize);
  EXPECT_GE(v.capacity(), inlineSize);
  vectorInvariant(v);
}

TEST(SmallVector, emptySize) {
  flo::SmallVector<int, 0x10, Testing::DefaultAllocator<int[]>> v;

  SmallVectorInvariant(v);

  EXPECT_EQ(v.size(), 0);
}

TEST(SmallVector, push_back) {
  Testing::forRandomInt([](uSz numElements) {
    numElements %= 0x1000;

    flo::SmallVector<int, 0x10, Testing::DefaultAllocator<int[]>> v;

    for(uSz i = 0; i < numElements; ++i) {
      auto val = Testing::urand(0x10000);
     
      v.push_back(val);

      SmallVectorInvariant(v);

      ASSERT_EQ(v.size(), i + 1);
      expectElement(v, i, val);
    }
  });
}

TEST(SmallVector, emplace) {
  flo::SmallVector<int, 0x10, Testing::DefaultAllocator<int[]>> v;
  Testing::forRandomInt([&v](int val) {
    auto pos = v.empty() ? 0 : Testing::urand(v.size() - 1);

    auto prevSize = v.size();

    v.emplace(v.begin() + pos, val);

    SmallVectorInvariant(v);

    ASSERT_EQ(v.size(), prevSize + 1);
    expectElement(v, pos, val);
  });
}

TEST(SmallVector, emplace_back) {
  Testing::forRandomInt([](int val) {
    flo::SmallVector<int, 0x10, Testing::DefaultAllocator<int[]>> v;

    v.emplace_back(val);

    SmallVectorInvariant(v);

    ASSERT_EQ(v.size(), 1);
    expectElement(v, 0, val);
  });
}

TEST(SmallVector, ModifySubscript) {
  flo::SmallVector<int, 0x10, Testing::DefaultAllocator<int[]>> v;
  v.reserve(0x100);

  while(v.size() != v.capacity()) {
    v.push_back(0);
    SmallVectorInvariant(v);
  }

  Testing::forRandomInt([&v](int val) {
    auto ind = Testing::urand(v.size() - 1);

    v[ind] = val;

    SmallVectorInvariant(v);

    expectElement(v, ind, val);
  });
}

TEST(SmallVector, DoCallDestructor) {
  struct S {
    S(bool &tf)
      : testFailed{tf} { }
    ~S() { testFailed = false; }
  private:
    bool &testFailed;
  };

  bool testFailed = true;

  {
    flo::SmallVector<S, 0x10, Testing::DefaultAllocator<S[]>> v;
    v.emplace_back(testFailed);
  }

  if(testFailed)
    ADD_FAILURE();
}

TEST(SmallVector, Reserve) {
  Testing::forRandomInt([](uSz cap) {
    flo::SmallVector<int, 0x10, Testing::DefaultAllocator<int[]>> v;

    cap %= 0x10000;

    v.reserve(cap);
    SmallVectorInvariant(v);
    EXPECT_GE(v.capacity(), cap);
  });
}
