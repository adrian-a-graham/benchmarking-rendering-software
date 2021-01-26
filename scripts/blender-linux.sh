#!/bin/bash -x

# Copyright 2019 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Report start.
echo "`date`: ********* START $0 BENCHMARK SETUP *********"

# Software GCS buckets. This should be queried from config at some point.
BENCHMARK_SOFTWARE_LOC=gs://benchmark-software
BENCHMARK_SCENE_LOC=gs://benchmark-scenes
BENCHMARK_SCRIPT_LOC=gs://benchmark-scripts
BENCHMARK_REPORT_LOC=gs://benchmark-reports
NUM_ROUNDS=6
NVIDIA_DRIVER=install-nvidia-driver-linux.sh
ACCELERATOR="CPU"

# Software-specific variables.
BENCHMARKS="bmw27 classroom fishy_cat koro pavillon_barcelona"
TMPDIR=/tmp
INSTALLER_NAME=blender-2.90.0-linux64.tar.xz
INSTALL_LOC=$TMPDIR/blender-2.90.0-linux64
SCRIPTS_BASE=blender-benchmark-script-2.0.1
SCENES_BASE=blender-benchmark-scenes
TAR_GZ=tar.gz
EXE=$INSTALL_LOC/blender

# Query instance metadata.
INSTANCE_NAME=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/name -H 'Metadata-Flavor: Google')
INSTANCE_ZONE=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/zone -H 'Metadata-Flavor: Google')
SESSION=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/attributes/session -H 'Metadata-Flavor: Google')
DELETE=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/attributes/delete -H 'Metadata-Flavor: Google')

# If 'gpu' is found in instance name, this is a GPU render.
if [[ $INSTANCE_NAME = *gpu* ]]; then
  echo "GPU render requested."
  ACCELERATOR="CUDA"

  # Install NVIDIA GRID driver.
  gsutil -m cp $BENCHMARK_SCRIPT_LOC/$NVIDIA_DRIVER $TMPDIR/$NVIDIA_DRIVER
  /bin/bash $TMPDIR/$NVIDIA_DRIVER
fi

BENCHMARK_REPORT_TMP=$TMPDIR/benchmark-reports/$SESSION
mkdir -p $BENCHMARK_REPORT_TMP
REPORT_FILE=$BENCHMARK_REPORT_TMP/$INSTANCE_NAME.$$.json

# Download and extract benchmark scripts.
gsutil -m cp $BENCHMARK_SOFTWARE_LOC/$SCRIPTS_BASE.$TAR_GZ $TMPDIR
tar xfz $TMPDIR/$SCRIPTS_BASE.$TAR_GZ --directory $TMPDIR

# Download and extract benchmark scenes.
gsutil -m cp $BENCHMARK_SCENE_LOC/$SCENES_BASE.$TAR_GZ $TMPDIR
tar xfz $TMPDIR/$SCENES_BASE.$TAR_GZ --directory $TMPDIR

#### BEGIN Software-specific commands. ####

# Install Blender-specific libs.
apt-get update
apt-get install -y \
  libxi-dev \
  libxxf86vm-dev \
  libxrender1 \
  libxi6 \
  libxxf86vm1 \
  libxrender1 \
  libgl1-mesa-glx \
  libxfixes-dev

# Download and install Blender 2.90.0.
if [ $ACCELERATOR = "CPU" ] || [[ $INSTANCE_NAME = *-a2-* ]]; then
  echo "`date`: *** Installing from archive. ***"
  # This version has CPU rendering optimized.
  gsutil -m cp $BENCHMARK_SOFTWARE_LOC/$INSTALLER_NAME $TMPDIR
  tar xf $TMPDIR/$INSTALLER_NAME --directory $TMPDIR
else
  echo "`date`: *** Installing from repo. ***"
  # This version works with multi-GPUs, but not the A100's. Unsure why.
  add-apt-repository -y ppa:thomas-schiex/blender
  apt-get update
  apt-get install -y blender
  EXE=/usr/bin/blender
fi

# Report and start timer.
echo "`date`: ********* START $0 BENCHMARKS *********"

# Run the benchmark 5x and average results.
for ROUND in $(seq 1 $NUM_ROUNDS); do

  # Only start counting after the 1st round is complete for disk caching
  # purposes
  if [ $ROUND -eq 2 ]; then
    SECONDS=0
  fi

  echo "`date`: ********* START BENCHMARK $INSTANCE_NAME $ROUND *********"

  # Iterate over each benchmark and render. Write all logs to one file.
  for BENCHMARK in $BENCHMARKS; do

    echo "`date`: ********* START $BENCHMARK *********"

    $EXE \
      --background \
      --factory-startup \
      -noaudio \
      --enable-autoexec \
      --engine CYCLES \
      $TMPDIR/$SCENES_BASE/$BENCHMARK/main.blend \
      --python $TMPDIR/$SCRIPTS_BASE/main.py \
      -- \
      --device-type=$ACCELERATOR

    echo "`date`: ********* END $BENCHMARK *********"


  done # for BENCHMARK IN BENCHMARKS
  echo "ROUND $ROUND of $INSTANCE_NAME ended at $SECONDS" | tee -a $REPORT_FILE

done # for ROUND

# Report duration.
JSON="{\"benchmark type\": \"$INSTANCE_NAME\", \"total duration\": $SECONDS, \"average duration\": $((SECONDS/(NUM_ROUNDS-1)))}"
echo $JSON | tee -a $REPORT_FILE

# Push report to common bucket.
gsutil cp $REPORT_FILE $BENCHMARK_REPORT_LOC/$SESSION/

# Report.
echo "`date`: ********* END $0 BENCHMARKS *********"

# Delete instance.
if [ $DELETE -eq 1 ]; then
  echo "`date`: ********* DELETING INSTANCE $INSTANCE_NAME... *********"
  gcloud --quiet compute instances delete $INSTANCE_NAME --zone=$INSTANCE_ZONE
fi
