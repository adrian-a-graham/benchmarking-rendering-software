#!/bin/bash -x

# Copyright 2020 Google Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
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
ACCELERATOR="cpu"

# Software-specific variables. 
TMPDIR=/tmp
INSTALL_LOC=/opt/OctaneBench_2020_1_4_linux
INSTALLER_NAME=octaneBench_2020_1_4_linux.zip
OCTANE_EXTRACT=octane-extract.py
EXE=octane

# Query instance metadata.
INSTANCE_NAME=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/name -H 'Metadata-Flavor: Google')
INSTANCE_ZONE=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/zone -H 'Metadata-Flavor: Google')
SESSION=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/attributes/session -H 'Metadata-Flavor: Google')
DELETE=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/attributes/delete -H 'Metadata-Flavor: Google')

# If 'gpu' is found in instance name, this is a GPU render.
if [[ $INSTANCE_NAME = *gpu* ]]; then
  echo "GPU render requested."
  ACCELERATOR="gpu"

  # Install NVIDIA GRID driver.
  gsutil -m cp $BENCHMARK_SCRIPT_LOC/$NVIDIA_DRIVER $TMPDIR/$NVIDIA_DRIVER
  /bin/bash $TMPDIR/$NVIDIA_DRIVER
fi

if [[ $INSTANCE_NAME = *-a2-* ]]; then
  INSTALL_LOC=/opt/OctaneBench_2020_1_4_linux_a2
  INSTALLER_NAME=OctaneBench_2020_1_4_linux_a2.zip
  ACCELERATOR="gpu"
fi

BENCHMARK_REPORT_TMP=$TMPDIR/benchmark-reports/$SESSION
mkdir -p $BENCHMARK_REPORT_TMP
REPORT_FILE=$BENCHMARK_REPORT_TMP/$INSTANCE_NAME.$$.json
gsutil cp $BENCHMARK_SCRIPT_LOC/$OCTANE_EXTRACT $BENCHMARK_REPORT_TMP
chmod 755 $BENCHMARK_REPORT_TMP/$OCTANE_EXTRACT

# Download benchmark executable.
gsutil -m cp $BENCHMARK_SOFTWARE_LOC/$INSTALLER_NAME $TMPDIR
chmod 755 $TMPDIR/$INSTALLER_NAME

# Install Octane.
echo "`date`: ********* INSTALLING OCTANE *********"

apt install -y unzip
apt-get install -y libx11-6
apt-get install -y libxext6
unzip -d /opt $TMPDIR/$INSTALLER_NAME

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

  REPORT_FILE_ROUND=$REPORT_FILE-$ROUND

  # Run benchmark.
  echo "`date`: ********* START $BENCHMARK *********"
  $INSTALL_LOC/$EXE --benchmark --no-gui --quiet -a $REPORT_FILE_ROUND
  echo "`date`: ********* END $BENCHMARK *********"

  echo "Score: $($BENCHMARK_REPORT_TMP/$OCTANE_EXTRACT $REPORT_FILE_ROUND)" | tee -a $REPORT_FILE

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
