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
TIMESTR='Time: '

def extractTimes():

    timesRaw=[]
    results=[]

    # Extract raw data.
    with open(FILENAME) as f:
        data = f.readlines()
        for line in data:
            if TIMESTR in line:
                timesRaw.append(line.lstrip(TIMESTR).rstrip())
            # end if
        # end for
    # end with

    # Convert to seconds.
    for time in timesRaw:
        h, m, s = [re.sub('[^0-9]', '', i) for i in time.split(':')]
        results.append( (float(h)*3600) + float(m)*60 + float(s) )
    # end for

    # Pull average.
    averageResult = round( (sum(results) / len(results)), 3)
    return averageResult

# end def

print(extractTimes())
