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

# Set correct timezone.
timedatectl set-timezone America/Los_Angeles

# Set ffmpeg report file location.
export FFREPORT=file=/var/log/ffmpeg-$(date +%Y%m%s).log

# Report start.
echo "`date`: ********* START $0 BENCHMARK SETUP *********"

# Software GCS buckets. This should be queried from config at some point.
#BENCHMARK_SOFTWARE_LOC=gs://render-benchmark-software
#BENCHMARK_SCENE_LOC=gs://render-benchmark-scenes
BENCHMARK_SCRIPT_LOC=gs://render-benchmark-scripts
BENCHMARK_REPORT_LOC=gs://render-benchmark-reports
BENCHMARK_VIDEO_LOC=gs://render-benchmark-videos
NUM_ROUNDS=6
NVIDIA_DRIVER=install-nvidia-driver-linux.sh
ACCELERATOR="cpu"

# Software-specific variables. 
TMPDIR=/tmp
VIDEO_NAME=bbb_sunflower_2160p_30fps_normal.mp4
#VIDEO_NAME=bbb_sunflower_2160p_30fps_short.mp4 #<-- very short for testing

# Query instance metadata.
INSTANCE_NAME=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/name -H 'Metadata-Flavor: Google')
INSTANCE_ZONE=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/zone -H 'Metadata-Flavor: Google')
SESSION=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/attributes/session -H 'Metadata-Flavor: Google')
DELETE=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/attributes/delete -H 'Metadata-Flavor: Google')
RESOLUTION_Y=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/attributes/resolution -H 'Metadata-Flavor: Google')

# If 'gpu' is found in instance name, this is a GPU render.
if [[ $INSTANCE_NAME = *gpu* ]]; then
  echo "GPU acceleration requested."
  ACCELERATOR="gpu"

  # Install NVIDIA GRID driver.
  gcloud storage -m cp $BENCHMARK_SCRIPT_LOC/$NVIDIA_DRIVER $TMPDIR/$NVIDIA_DRIVER
  /bin/bash $TMPDIR/$NVIDIA_DRIVER
fi

#if [[ $INSTANCE_NAME = *-a2-* ]]; then
#  INSTALL_LOC=/opt/OctaneBench_2020_1_4_linux_a2
#  INSTALLER_NAME=OctaneBench_2020_1_4_linux_a2.zip
#  ACCELERATOR="gpu"
#fi

BENCHMARK_REPORT_TMP=$TMPDIR/benchmark-reports/$SESSION
mkdir -p $BENCHMARK_REPORT_TMP
REPORT_FILE=$BENCHMARK_REPORT_TMP/$INSTANCE_NAME.$$.json

# Download video file.
gcloud storage cp $BENCHMARK_VIDEO_LOC/$VIDEO_NAME $TMPDIR
#chmod 755 $BENCHMARK_REPORT_TMP/$OCTANE_EXTRACT

# Download benchmark executable.
#gcloud storage -m cp $BENCHMARK_SOFTWARE_LOC/$INSTALLER_NAME $TMPDIR
#chmod 755 $TMPDIR/$INSTALLER_NAME

# Install ffmpeg.
echo "`date`: ********* INSTALLING FFMPEG *********"

apt update
sudo apt install -y ffmpeg
sudo apt-get install -y libaom-dev \
  libass-dev \
  libfdk-aac-dev \
  libnuma-dev \
  libopus-dev \
  libvorbis-dev \
  libvpx-dev \
  libx264-dev \
  libx265-dev nasm

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
  
  lscpu | grep -q avx512
  [[ $? = 0 ]] && _ASM="avx512" || _ASM="avx2"

  ffmpeg \
    -i $TMPDIR/$VIDEO_NAME \
    -report \
    -c:v libx264 \
    -filter:v scale="-2:$RESOLUTION_Y" \
    -preset:v medium \
    -x264-params "keyint=120:min-keyint=120:sliced-threads=0:scenecut=0:asm=${_ASM}" \
    -tune psnr -profile:v high -b:v 6M -maxrate 12M -bufsize 24M \
    -c:a copy \
    -y \
    $TMPDIR/$VIDEO_NAME-$RESOLUTION_Y.mp4

  echo "`date`: ********* END $BENCHMARK *********"

  echo "round=$REPORT_FILE_ROUND, seconds=$SECONDS" | tee -a $REPORT_FILE

done # for ROUND

# Report duration.
JSON="{\"benchmark type\": \"$INSTANCE_NAME\", \"total duration\": $SECONDS, \"average duration\": $((SECONDS/(NUM_ROUNDS-1)))}"
echo $JSON | tee -a $REPORT_FILE

# Push report to common bucket.
gcloud storage cp $REPORT_FILE $BENCHMARK_REPORT_LOC/$SESSION/

# Report.
echo "`date`: ********* END $0 BENCHMARKS *********"

# Delete instance.
if [ $DELETE -eq 1 ]; then
  echo "`date`: ********* DELETING INSTANCE $INSTANCE_NAME... *********"
  gcloud --quiet compute instances delete $INSTANCE_NAME --zone=$INSTANCE_ZONE
fi
