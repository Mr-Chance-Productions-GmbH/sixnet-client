#!/bin/bash
# Usage: write-cask-dev.sh VERSION SHA OUTPUT_FILE
set -e
VERSION=$1
SHA=$2
OUTPUT=$3

cat > "$OUTPUT" << CASK
cask "sixnet-client-dev" do
  version "${VERSION}"
  sha256 "${SHA}"
  url "https://github.com/Mr-Chance-Productions-GmbH/sixnet-client/releases/download/dev/SixnetClient-dev-${VERSION}.dmg"

  name "Sixnet Client (dev)"
  desc "Development channel — macOS menu bar VPN client for sixnet"
  homepage "https://github.com/Mr-Chance-Productions-GmbH/sixnet-client"

  depends_on formula: "Mr-Chance-Productions-GmbH/sixnet/sixnetd"

  app "SixnetClient Dev.app"

  postflight do
    system_command "/usr/bin/xattr",
      args: ["-rd", "com.apple.quarantine", "#{appdir}/SixnetClient Dev.app"]
  end
end
CASK
