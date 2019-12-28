#include "flo/Containers/Sorted.hpp"
#include "Testing.hpp"

#include <vector>

TEST(Sorted, elements) {
  uSz elements[] {
    Testing::urand(),
    Testing::urand(),
    Testing::urand(),
    Testing::urand(),
    Testing::urand(),
    Testing::urand(),
    Testing::urand(),
  };

  flo::Sorted<std::vector<uSz>> v;
  for(auto &ele: elements)
    v.insert(ele);

  std::sort(std::begin(elements), std::end(elements));

  EXPECT_THAT(v, ElementsAreArray(elements));
}

TEST(Sorted, find) {
  flo::Sorted<std::vector<uSz>> v;
  v.insert(5);
  v.insert(4);
  v.insert(3);
  v.insert(2);

  EXPECT_EQ(v.find(4), v.begin() + 2);
}

TEST(Sorted, contains) {
  flo::Sorted<std::vector<uSz>> v;
  v.insert(5);
  v.insert(4);
  v.insert(3);
  v.insert(2);

  EXPECT_EQ(v.contains(4), true);
  EXPECT_EQ(v.contains(1), false);
}

TEST(Sorted, count) {
  flo::Sorted<std::vector<uSz>> v;
  for(int i = 0; i < 20; ++ i)
    v.insert(5);

  for(int i = 0; i < 5; ++ i)
    v.insert(4);

  EXPECT_EQ(v.count(6), 0);
  EXPECT_EQ(v.count(5), 20);
  EXPECT_EQ(v.count(4), 5);
  EXPECT_EQ(v.count(3), 0);
}
