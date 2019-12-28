#include "flo/Containers/Unsorted.hpp"
#include "Testing.hpp"

#include <vector>

TEST(Unsorted, find) {
  flo::Unsorted<std::vector<uSz>> v;
  v.emplace_back(5);
  v.emplace_back(4);
  v.emplace_back(3);
  v.emplace_back(2);

  auto found = v.find(4);
  ASSERT_NE(found, v.end());
  EXPECT_EQ(*found, 4);
}

TEST(Unsorted, contains) {
  flo::Unsorted<std::vector<uSz>> v;
  v.emplace_back(5);
  v.emplace_back(4);
  v.emplace_back(3);
  v.emplace_back(2);

  EXPECT_EQ(v.contains(4), true);
  EXPECT_EQ(v.contains(1), false);
}

TEST(Unsorted, count) {
  flo::Unsorted<std::vector<uSz>> v;
  for(int i = 0; i < 20; ++ i)
    v.emplace_back(5);

  for(int i = 0; i < 5; ++ i)
    v.emplace_back(4);

  EXPECT_EQ(v.count(6), 0);
  EXPECT_EQ(v.count(5), 20);
  EXPECT_EQ(v.count(4), 5);
  EXPECT_EQ(v.count(3), 0);
}
