cask "baro" do
  version "1.3.0"
  sha256 :no_check

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
