#!/bin/bash -x

# Copyright 2024 Google LLC
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     https://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

echo "`date`: ********* START $0 STARTUP SCRIPT *********"

# Software GCS buckets. This should be queried from config at some point.
BENCHMARK_SCRIPT_LOC=gs://render-benchmark-scripts
SCRIPT_EXE="ffmpeg-linux.sh"
TMPDIR=/tmp

# Download script.
gcloud storage cp $BENCHMARK_SCRIPT_LOC/$SCRIPT_EXE $TMPDIR
/bin/bash $TMPDIR/$SCRIPT_EXE &
