require "formula"

class Clawrtc < Formula
  desc "Mine RTC tokens - PowerPC G4/G5 get 2.0-2.5x multiplier!"
  homepage "https://bottube.ai"
  # refs/heads/main is a moving target: it can never carry a sha256, and the
  # contents change under users between two installs of the same "1.6.0".
  # Pinned to the tagged miner snapshot, which contains miners/ppc/.
  url "https://github.com/Scottcjn/Rustchain/archive/refs/tags/v3.1.2-miner.tar.gz"
  version "1.6.0"
  sha256 "79f603a1a63259eb2baf4744cfc93863809b485d51cc02794aec91ee08a5f81d"

  # The miner is Python 3 only ("#!/usr/bin/env python3", f-strings throughout).
  # Tigerbrew's "python" formula is 2.7.18, which cannot parse it.
  depends_on "python3"

  # The miner does "import requests" at module scope and Tigerbrew has no
  # requests formula, so vendor it together with its four install_requires.
  # These versions are the newest sdists that still ship a setup.py:
  # Language::Python.setup_install_args drives setup.py directly, and
  # idna >= 3 / urllib3 >= 2 are PEP 517-only (no setup.py to execute).
  resource "certifi" do
    url "https://files.pythonhosted.org/packages/c2/02/a95f2b11e207f68bc64d7aae9666fed2e2b3f307748d5123dffb72a1bbea/certifi-2024.7.4.tar.gz"
    sha256 "5a1e7645bc0ec61a09e26c36f6106dd4cf40c6db3a1fb6352b0244e7fb057c7b"
  end

  resource "charset-normalizer" do
    url "https://files.pythonhosted.org/packages/56/31/7bcaf657fafb3c6db8c787a865434290b726653c912085fbd371e9b92e1c/charset-normalizer-2.0.12.tar.gz"
    sha256 "2857e29ff0d34db842cd7ca3230549d1a697f96ee6d3fb071cfa6c7393832597"
  end

  resource "idna" do
    url "https://files.pythonhosted.org/packages/ea/b7/e0e3c1c467636186c39925827be42f16fee389dc404ac29e930e9136be70/idna-2.10.tar.gz"
    sha256 "b307872f855b18632ce0c21c5e45be78c0ea7ae4c15c828c20788b26921eb3f6"
  end

  resource "urllib3" do
    url "https://files.pythonhosted.org/packages/e4/e8/6ff5e6bc22095cfc59b6ea711b687e2b7ed4bdb373f7eeec370a97d7392f/urllib3-1.26.20.tar.gz"
    sha256 "40c2dc0c681e47eb8f90e7e27bf6ff7df2e677421fd46756da1161c39ca70d32"
  end

  resource "requests" do
    url "https://files.pythonhosted.org/packages/9d/be/10918a2eac4ae9f02f6cfe6414b7a155ccd8f7f9d4380d62fd5b955065c3/requests-2.31.0.tar.gz"
    sha256 "942c5a758f98d790eaed1a29cb6eefc7ffb0d1cf7af05c3d2791656dbd6ad1e1"
  end

  def install
    python_version = Language::Python.major_minor_version "python3"
    site_packages = libexec/"vendor/lib/python#{python_version}/site-packages"
    ENV.prepend_create_path "PYTHONPATH", site_packages

    resources.each do |r|
      r.stage { system "python3", *Language::Python.setup_install_args(libexec/"vendor") }
    end

    # The PowerPC miner lives in miners/ppc/ and is the one that takes the
    # --wallet flag advertised in the caveats below.
    # "miners/rustchain_universal_miner.py" does not exist in the RustChain
    # repo at any tag, so the old install line aborted every build with
    # Errno::ENOENT before anything reached the Cellar.
    libexec.install "miners/ppc/rustchain_powerpc_g4_miner_v2.2.2.py" => "clawrtc_miner.py"

    python3 = Formula["python3"].opt_bin/"python3"
    (bin/"clawrtc").write <<~EOS
      #!/bin/bash
      export PYTHONPATH="#{site_packages}${PYTHONPATH:+:$PYTHONPATH}"
      exec "#{python3}" "#{libexec}/clawrtc_miner.py" "$@"
    EOS
  end

  def caveats
    <<~EOS
      ClawRTC on PowerPC Mac — you're earning bonus multipliers!

        PowerPC G4: 2.5x reward multiplier
        PowerPC G5: 2.0x reward multiplier

      Quick start:
        clawrtc --wallet my-g4-miner

      Your vintage hardware earns MORE than modern machines.
      Real iron only — VMs get nothing.

      More info: https://bottube.ai
    EOS
  end

  test do
    # Runs the wrapper Homebrew actually links, so one command covers the
    # interpreter, the installed script and the vendored imports: the miner
    # does "import requests" at module scope, so --help only reaches argparse
    # if the vendor directory really is on PYTHONPATH.
    output = shell_output("#{bin}/clawrtc --help")
    assert_match(/usage:/, output)
    assert_match(/--wallet/, output)
  end
end
