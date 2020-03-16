#pragma once

#include "flo/Containers/Iterator.hpp"

template<typename Vec, typename Ty>
void expectElement(Vec const &v, uSz index, Ty const &value) {
  ASSERT_LT(index, v.size());
  if(index < v.size()) {
    EXPECT_EQ(*(v.begin() + index), value);
    EXPECT_EQ(v[index], value);

    if(index == v.size() - 1) {
      EXPECT_EQ(v.back(), value);
    }

    if(index == 0) {
      EXPECT_EQ(v.front(), value);
    }
  }
}

template<typename Vec>
void vectorInvariant(Vec &vec) {
  EXPECT_EQ(vec.size(), flo::distance(vec.begin(),   vec.end()));
  EXPECT_EQ(vec.size(), flo::distance(vec.rbegin(),  vec.rend()));
  EXPECT_EQ(vec.size(), flo::distance(vec.crbegin(), vec.crend()));
  EXPECT_EQ(vec.size(), flo::distance(vec.cbegin(),  vec.cend()));
  EXPECT_LE(vec.size(), vec.capacity());
  EXPECT_EQ(vec.size() == 0, vec.empty());

  if(vec.size()) {
    EXPECT_EQ(vec.data(), vec.begin());
  }

  if(vec.capacity()) {
    EXPECT_NE(vec.data(), nullptr);
  }

  // All elements accessible, assume some address santization is running
  for(typename Vec::value_type &v: vec) {
    auto *t = reinterpret_cast<volatile char *>(&v);
    for(auto p = t; p != t + sizeof(v); ++ p)
      *p = *p;
  }
}
