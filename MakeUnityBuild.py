#!/usr/bin/env python

from sys import argv

import random

files = argv[1:]

# To make sure no one relies on the order. Please don't.
random.shuffle(files)

for f in files:
  print('#include "' + f + '"')
