#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

bash -n Scripts/build-app.sh
bash -n Scripts/release.sh
swift test
python3 Scripts/test-build-app.py
python3 Scripts/test-homebrew-tap.py
python3 Scripts/test-publish-release.py
