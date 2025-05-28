#!/usr/bin/env bash
set -euo pipefail

echo "🧼 Running SONA ISO full maintenance..."

echo "1️⃣ Validating repo packages..."
bash ./check-main-repo-packages.sh

echo
echo "2️⃣ Cleaning invalid packages from packages.x86_64..."
bash ./clean-packages.sh

echo
echo "3️⃣ Updating installer script..."
bash ./clean-installer.sh

echo "✅ Done. You're ready to run mkarchiso or boot via QEMU!"
