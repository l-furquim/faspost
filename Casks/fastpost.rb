cask "fastpost" do
  version "1.0.0"
  sha256 "5335b764ab25bfbce8130910bb16bbdaa906f2302ee9417c6f59c89ef6284051"

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
