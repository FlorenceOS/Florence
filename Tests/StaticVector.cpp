#include "flo/Containers/StaticVector.hpp"

#include "Testing.hpp"
#include "VectorTests.hpp"

template<typename T, auto maxSize>
void StaticVectorInvariant(flo::StaticVector<T, maxSize> &v) {
  vectorInvariant(v);
  EXPECT_EQ(v.capacity(), maxSize);
}

TEST(StaticVector, emptySize) {
  flo::StaticVector<int, 0x10> v;

  StaticVectorInvariant(v);

  EXPECT_EQ(v.size(), 0);
}

TEST(StaticVector, reserve) {
  flo::StaticVector<int, 0x10> v;
  v.reserve(1);

  StaticVectorInvariant(v);

  EXPECT_GT(v.capacity(), 0);
}

TEST(StaticVector, push_back) {
  Testing::forRandomInt([](int val) {
    flo::StaticVector<int, 0x10> v;

    v.push_back(val);

    StaticVectorInvariant(v);

    ASSERT_EQ(v.size(), 1);
    expectElement(v, 0, val);
  });
}

TEST(StaticVector, emplace) {
  Testing::forRandomInt([](int val) {
    flo::StaticVector<int, 0x10> v;

    v.emplace(v.end(), val);

    StaticVectorInvariant(v);

    ASSERT_EQ(v.size(), 1);
    expectElement(v, 0, val);
  });
}

TEST(StaticVector, emplace_back) {
  Testing::forRandomInt([](int val) {
    flo::StaticVector<int, 0x10> v;

    v.emplace_back(val);

    StaticVectorInvariant(v);

    ASSERT_EQ(v.size(), 1);
    expectElement(v, 0, val);
  });
}

TEST(StaticVector, ModifySubscript) {
  Testing::forRandomInt([](int val) {
    flo::StaticVector<int, 0x10> v;
    while(v.size() != v.capacity())
      v.push_back(0);

    auto ind = Testing::urand(v.size() - 1);

    v[ind] = val;

    StaticVectorInvariant(v);

    expectElement(v, ind, val);
  });
}

TEST(StaticVector, DoCallDestructor) {
  struct S {
    S(bool &tf)
      : testFailed{tf} { }
    ~S() { testFailed = false; }
  private:
    bool &testFailed;
  };

  bool testFailed = true;

  {
    flo::StaticVector<S, 0x10> v;
    v.emplace_back(testFailed);
  }

  if(testFailed)
    ADD_FAILURE();
}

TEST(StaticVector, DoNotCallDestructor) {
  struct S {
    ~S() { ADD_FAILURE(); }
  };

  flo::StaticVector<S, 0x10, false> v;
  v.emplace_back();
}

TEST(StaticVector, CallDestructorEraseOnly) {
  struct S {
    S(bool &testFailed, bool shouldDestruct)
      : shouldDestruct{shouldDestruct}
      , testFailed{testFailed}
    { }

    ~S() {
      if(!shouldDestruct) testFailed = true;
    }
  private:
    bool shouldDestruct;
    bool &testFailed;
  };

  bool testFailed = false;

  {
    flo::StaticVector<S, 0x10, false> v;
    v.emplace_back(testFailed, false);
    v.emplace_back(testFailed, true);
    v.pop_back();
  }

  if(testFailed)
    ADD_FAILURE();
}
