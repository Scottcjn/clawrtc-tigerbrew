require "formula"

class Clawrtc < Formula
  desc "Mine RTC tokens - PowerPC G4/G5 get 2.0-2.5x multiplier!"
  homepage "https://bottube.ai"
  # Pinned to a commit, not a branch. A branch tarball changes under users'
  # feet, and with an empty sha256 there was nothing to detect that it had.
  url "https://github.com/Scottcjn/Rustchain/archive/19c1fd029b89de9f5b97da3432d3eb12829f6d95.tar.gz"
  version "1.6.0"
  sha256 "cfbc146749b369ddf7ee269e0c7fe0739492109b44bc9f82721eaf1aae1471ed"

  depends_on "python"

  def install
    # The miner lives under deprecated/old_miners/. It has since 2025-12-24,
    # which is before this formula was written, so the previous path never
    # resolved and the install always failed after the download.
    libexec.install "deprecated/old_miners/rustchain_universal_miner.py"

    (bin/"clawrtc").write <<~EOS
      #!/bin/bash
      exec python #{libexec}/rustchain_universal_miner.py "$@"
    EOS
    chmod 0755, bin/"clawrtc"
  end

  def caveats
    <<~EOS
      ClawRTC on PowerPC Mac — you're earning bonus multipliers!

        PowerPC G4: 2.5x reward multiplier
        PowerPC G5: 2.0x reward multiplier

      The miner needs the `requests` module:
        python -m pip install requests

      Quick start:
        clawrtc --wallet my-g4-miner

      Your vintage hardware earns MORE than modern machines.
      Real iron only — VMs get nothing.

      More info: https://bottube.ai
    EOS
  end

  test do
    assert_predicate libexec/"rustchain_universal_miner.py", :exist?
  end
end
