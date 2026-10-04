cask "space-disk-free" do
  version "@VERSION@"
  sha256 "@SHA256@"

  url "https://github.com/guilhermehrcosta/space-disk-free/releases/download/@TAG_PREFIX@#{version}/SpaceDiskFree-#{version}.dmg"
  name "Space Disk Free"
  desc "Menu bar app that shows what uses disk space and cleans it up"
  homepage "https://github.com/guilhermehrcosta/space-disk-free"

  depends_on macos: :sonoma

  app "Space Disk Free.app"

  uninstall quit: "com.guilhermecosta.SpaceDiskFree"

  zap trash: [
    "~/Library/Caches/com.guilhermecosta.SpaceDiskFree",
    "~/Library/HTTPStorages/com.guilhermecosta.SpaceDiskFree",
    "~/Library/Preferences/com.guilhermecosta.SpaceDiskFree.plist",
  ]

  caveats <<~EOS
    Space Disk Free is not signed with an Apple Developer ID, so macOS blocks its first launch.
    Open the app once, then go to System Settings > Privacy & Security and click "Open Anyway".
  EOS
end
