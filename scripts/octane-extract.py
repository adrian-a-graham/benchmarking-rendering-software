#!/usr/bin/env python3

# Copyright 2020 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
# See the License for the specific language governing permissions and
# limitations under the License.

import re,sys
FILENAME=sys.argv[1:][0]
SCORESTR='Total score:'

def extractScore():

    NEXT=False

    # Extract raw data.
    with open(FILENAME) as f:
        data = f.readlines()
        for line in data:
            if NEXT:
                SCORE=line.rstrip()
                return SCORE
            # end if 
            if SCORESTR in line:
                NEXT=True
                continue
            # end if

        # end for
    # end with

# end def

print(extractScore())
