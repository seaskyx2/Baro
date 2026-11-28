cask "baro" do
  version "1.4.2"
  sha256 "3631885f995ab5eb8e2b987f8f2aecaa25584a2c2c7569d38bb390f726f2aa87"

  url "https://github.com/seaskyx2/Baro/releases/download/v#{version}/Baro-v#{version}-macOS-arm64.zip"
  name "Baro"
  desc "Pure read-only, zero-intrusion system status monitor for macOS"
  homepage "https://github.com/seaskyx2/Baro"

  depends_on arch: :arm64
  depends_on macos: ">= :sequoia"

  app "Baro.app"

  postflight do
    system_command "/usr/bin/xattr", args: ["-cr", "#{appdir}/Baro.app"]
  end

  zap trash: [
    "~/Library/Preferences/com.baro.monitor.plist"
  ]
end
