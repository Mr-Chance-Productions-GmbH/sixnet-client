#!/bin/bash
# Usage: write-cask.sh VERSION SHA OUTPUT_FILE
set -e
VERSION=$1
SHA=$2
OUTPUT=$3

cat > "$OUTPUT" << CASK
cask "sixnet-client" do
  version "${VERSION}"
  sha256 "${SHA}"
  url "https://github.com/Mr-Chance-Productions-GmbH/sixnet-client/releases/download/v${VERSION}/SixnetClient-${VERSION}.dmg"

  name "Sixnet Client"
  desc "macOS menu bar VPN client for sixnet"
  homepage "https://github.com/Mr-Chance-Productions-GmbH/sixnet-client"

  depends_on formula: "Mr-Chance-Productions-GmbH/sixnet/sixnetd"

  app "SixnetClient.app"
end
CASK
