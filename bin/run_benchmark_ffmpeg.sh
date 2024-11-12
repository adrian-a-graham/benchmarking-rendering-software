#!/bin/sh

# Copyright 2020 Google Inc.
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

# Define defaults.
AVAILABLE_BENCHMARKS="ffmpeg"
AVAILABLE_RESOLUTIONS="sd hd"
ACCELERATOR=cpu
ACCEL_INFO=$ACCELERATOR
OS=linux
VERBOSE=0
ZONE="us-central1-a"
DELETE=1
RESOLUTION="sd"

POSITIONAL=()
while [[ $# -gt 0 ]]
do
key="$1"

case $key in
  -c|--config)
  CONFIG_FILE="$2"
  if [[ ! -f $CONFIG_FILE ]]; then
    echo "File $CONFIG_FILE doesn't exist."
    exit 1
  fi
  shift # past argument
  shift # past value
  ;;
  -b|--benchmark)
  BENCH_TYPE="$2"
  if [[ ! $BENCH_TYPE =~ ffmpeg ]]; then
    echo "Invalid benchmark. Must be one of $AVAILABLE_BENCHMARKS."
    exit 1
  fi
  shift # past argument
  shift # past value
  ;;
  -a|--accelerator)
  ACCELERATOR="$2"
  shift # past argument
  shift # past value
  ;;
  -o|--os)
  OS="$2"
  shift # past argument
  shift # past value
  ;;
  -z|--zone)
  ZONE="$2"
  shift # past argument
  shift # past value
  ;;
  --no-delete)
  DELETE=0
  shift # past argument
  ;;
  -r|--resolution)
  RESOLUTION="$2"
  if [[ ! $RESOLUTION =~ sd|hd ]]; then
    echo "Invalid resolution. Must be one of $AVAILABLE_RESOLUTIONS."
    exit 1
  fi
  shift # past argument
  shift # past value
  ;;
  -v|--verbose)
  VERBOSE=1
  shift # past argument
  ;;
  -n|--noop)
  NOOP=echo
  shift # past argument
  ;;
esac
done
set -- "${POSITIONAL[@]}" # restore positional parameters

if [ $VERBOSE -eq 1 ]; then
  echo "BENCH_TYPE=$BENCH_TYPE"
  echo "ACCELERATOR=$ACCELERATOR"
  echo "OS=$OS"
fi

SESSION_INFO=$BENCH_TYPE-$(date +'%Y%m%dt%H%M')-$ACCELERATOR

# Read configs.
CONFIGS=$(<$CONFIG_FILE)
#CONFIGS=$(<./${ACCELERATOR}_configs.sh)

# Set up vars.
PROJECT="benchmarking-rendering-sw"
STARTUP_SCRIPT_URL="gs://render-benchmark-scripts/$BENCH_TYPE-$OS.sh"
IMAGE="ubuntu-2204-jammy-v20240927"
IMAGE_PROJECT="ubuntu-os-cloud"
BOOT_DISK_SIZE="10GB"

if [[ $OS == "windows" ]]; then
  IMAGE="windows-server-2019-dc-v20200714"
  IMAGE_PROJECT="windows-cloud"
  BOOT_DISK_SIZE="50GB"
fi

RESOLUTION_Y=480
if [[ $RESOLUTION == "hd" ]]; then
  RESOLUTION_Y=1080
fi

for CONFIG in $CONFIGS; do

  if [[ $CONFIG = \#* ]]; then
    continue
  fi

  if [ $ACCELERATOR == 'gpu' ]; then
    ACCEL_TYPE=`echo $CONFIG | awk -F',' {'print $1'}`
    ACCEL_COUNT=`echo $CONFIG | awk -F',' {'print $2'}`
    ACCEL_ZONE=`echo $CONFIG | awk -F',' {'print $3'}`
    ZONE="us-central1-$ACCEL_ZONE"
    CONFIG='n1-standard-8'
    ACCEL_STR="--accelerator=type=${ACCEL_TYPE},count=${ACCEL_COUNT}"
    ACCEL_INFO="gpu-$ACCEL_TYPE-$ACCEL_COUNT"
    MAINT_STR="--maintenance-policy=TERMINATE"
  fi

  # A2's are a special case. Launch like CPU instances but add 'gpu' to the machine name.
  if [[ $CONFIG = a2-* ]]; then
    BOOT_DISK_SIZE="100GB"
    ACCEL_INFO="gpu"
    MAINT_STR="--maintenance-policy=TERMINATE"
  fi

  # N4's and C4's only have hyperdisk-balanced. Also specify iops and throughput.
  # Default boot disk attributes.
  BOOT_DISK_TYPE="pd-ssd"
  IOPS=3060
  THROUGHPUT=155

  HYPERDISK_STR=""
  if [[ $CONFIG = c4-* ]] || [[ $CONFIG = n4-* ]]; then
    BOOT_DISK_TYPE="hyperdisk-balanced"
    HYPERDISK_STR="provisioned-iops=3060,provisioned-throughput=155,"
  fi

  INSTANCE_NAME=$BENCH_TYPE-$CONFIG-$ACCEL_INFO

  # Build create command.
  CMD="gcloud compute \
  instances create $INSTANCE_NAME \
  --project=$PROJECT \
  --zone=$ZONE \
  --async \
  --no-address \
  --quiet \
  --machine-type=$CONFIG \
  $ACCEL_STR \
  --metadata=\
'startup-script-url=$STARTUP_SCRIPT_URL,session=$SESSION_INFO,benchmark=$BENCH_TYPE,delete=$DELETE,enable-oslogin=true,resolution=$RESOLUTION_Y' \
  --create-disk=\
auto-delete=yes,\
boot=yes,\
device-name=$INSTANCE_NAME,\
image=projects/$IMAGE_PROJECT/global/images/$IMAGE,\
mode=rw,\
type=$BOOT_DISK_TYPE,\
size=$BOOT_DISK_SIZE,\
$HYPERDISK_STR \
  --scopes=https://www.googleapis.com/auth/devstorage.read_write,https://www.googleapis.com/auth/compute \
  --shielded-secure-boot \
  $MAINT_STR"

  # If verbose, echo creation command.
  if [ $VERBOSE ]; then
    echo ""
    echo "**** CREATING $CONFIG ****"
    echo $CMD
  fi

  # If not NOOP, run create command.
  if [ ! $NOOP ]; then
    eval $CMD
  fi

done
