cask "fastpost" do
  version "0.0.0"
  sha256 "0000000000000000000000000000000000000000000000000000000000000000"

  url "https://github.com/l-furquim/faspost/releases/download/v#{version}/Fastpost-#{version}.dmg"
  name "Fastpost"
  desc "Native macOS HTTP client"
  homepage "https://github.com/l-furquim/faspost"

  depends_on macos: ">= :tahoe"

  app "Fastpost.app"

  zap trash: [
    "~/Library/Preferences/furqas.fastpost.plist",
  ]

  caveats <<~EOS
    Fastpost is not notarized yet. First launch: right-click the app and choose Open,
    or run: xattr -cr /Applications/Fastpost.app
  EOS
end
