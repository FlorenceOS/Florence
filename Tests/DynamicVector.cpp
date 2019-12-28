#include "flo/Containers/DynamicVector.hpp"

#include "Testing.hpp"
#include "VectorTests.hpp"

template<typename T, typename Alloc>
void DynamicVectorInvariant(flo::DynamicVector<T, Alloc> const &v) {
  vectorInvariant(v);
}

TEST(DynamicVector, emptySize) {
  flo::DynamicVector<int, Testing::DefaultAllocator<int>> v;

  DynamicVectorInvariant(v);

  EXPECT_EQ(v.size(), 0);
}

TEST(DynamicVector, reserve) {
  flo::DynamicVector<int, Testing::DefaultAllocator<int>> v;
  v.reserve(1);

  DynamicVectorInvariant(v);

  EXPECT_GT(v.capacity(), 0); 
}

TEST(DynamicVector, push_back) {
  Testing::forRandomInt([](int val) {
    flo::DynamicVector<int, Testing::DefaultAllocator<int>> v;

    v.push_back(val);

    DynamicVectorInvariant(v);

    ASSERT_EQ(v.size(), 1);
    expectElement(v, 0, val);
  });
}

TEST(DynamicVector, emplace) {
  Testing::forRandomInt([](int val) {
    flo::DynamicVector<int, Testing::DefaultAllocator<int>> v;

    v.emplace(v.end(), val);

    DynamicVectorInvariant(v);

    ASSERT_EQ(v.size(), 1);
    expectElement(v, 0, val);
  });
}

TEST(DynamicVector, emplace_back) {
  Testing::forRandomInt([](int val) {
    flo::DynamicVector<int, Testing::DefaultAllocator<int>> v;

    v.emplace_back(val);

    DynamicVectorInvariant(v);

    ASSERT_EQ(v.size(), 1);
    expectElement(v, 0, val);
  });
}

TEST(DynamicVector, ModifySubscript) {
  flo::DynamicVector<int, Testing::DefaultAllocator<int>> v;
  v.reserve(0x1000);

  while(v.size() != v.capacity()) {
    v.push_back(0);
    DynamicVectorInvariant(v);
  }

  Testing::forRandomInt([&v](int val) {
    auto ind = Testing::urand(v.size() - 1);

    v[ind] = val;

    DynamicVectorInvariant(v);

    expectElement(v, ind, val);
  });
}

TEST(DynamicVector, DoCallDestructor) {
  struct S {
    S(bool &tf): testFailed{tf} { }
    ~S() { testFailed = false; }
  private:
    bool &testFailed;
  };

  bool testFailed = true;

  {
    flo::DynamicVector<S, Testing::DefaultAllocator<S>> v;
    v.emplace_back(testFailed);
  }

  if(testFailed)
    ADD_FAILURE();
}
