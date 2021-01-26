#!/bin/bash -x

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

echo "`date`: ********* START NVIDIA DRIVER INSTALL *********"

# Define globals.
TMPDIR="/tmp"

# Define NVIDIA driver location.
# Example:
# gs://nvidia-drivers-us-public/GRID/GRID12.0/NVIDIA-Linux-x86_64-460.32.03-grid.run
NVIDIA_BUCKET="gs://nvidia-drivers-us-public"
NVIDIA_GRID_VERSION="12.0"
#NVIDIA_EXE="NVIDIA-Linux-x86_64-450.51.05-grid.run"
NVIDIA_EXE="NVIDIA-Linux-x86_64-460.32.03-grid.run"
NVIDIA_DRIVER="$NVIDIA_BUCKET/GRID/GRID$NVIDIA_GRID_VERSION/$NVIDIA_EXE"

# Handle A2 instances (beta driver).
INSTANCE_NAME=$(curl -sX GET http://metadata.google.internal/computeMetadata/v1/instance/name -H 'Metadata-Flavor: Google')
#if [[ $INSTANCE_NAME = *-a2-* ]]; then
#
#  NVIDIA_EXE="cuda_11.0.3_450.51.06_linux.run"
#  NVIDIA_DRIVER="gs://benchmark-software/$NVIDIA_EXE"
#
#fi
echo "NVIDIA_DRIVER=$NVIDIA_DRIVER"

# Install gcc and make.
apt-get -y update && apt install -y gcc build-essential

# Verify the system has the correct kernel headers and development packages
# installed.
apt-get install -y linux-headers-$(uname -r)

gsutil -m cp $NVIDIA_DRIVER $TMPDIR
chmod 755 $TMPDIR/$NVIDIA_EXE

/bin/bash $TMPDIR/$NVIDIA_EXE --no-questions --ui=none --install-libglvnd
#if [[ $INSTANCE_NAME = *-a2-* ]]; then
#  /bin/bash $TMPDIR/$NVIDIA_EXE --silent
#else
#  /bin/bash $TMPDIR/$NVIDIA_EXE --no-questions --ui=none --install-libglvnd
#fi

# Verify installation.
nvidia-smi

echo "`date`: ********* END NVIDIA DRIVER INSTALL *********"
