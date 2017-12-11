#!/bin/bash
# Copyright 2017 Google Inc. All rights reserved.
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

set -x

# Download x264 if not available.
if [ ! -d x264 ]; then
  git clone http://git.videolan.org/git/x264.git
fi

# Check out the pinned x264 version.
pushd x264
git fetch
git checkout --detach 24899b0bf23345921da022f7a51e0c57dbe73d
# Build x264
./configure
make -j32
