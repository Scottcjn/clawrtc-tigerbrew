# frozen_string_literal: true

# Offline checks for Formula/clawrtc.rb.
#
# The formula cannot be exercised with real Homebrew here (Tigerbrew only runs
# on PowerPC Tiger/Leopard), so the DSL is stubbed and the install block is
# executed against fakes. Every assertion below corresponds to a way this
# formula was broken for every user on every machine:
#
#   * an empty sha256 on a refs/heads/main tarball (unverifiable, mutable)
#   * depends_on "python", which is Python 2.7.18 in Tigerbrew, for a
#     Python-3-only script
#   * libexec.install of a path that does not exist in the tarball
#   * a wrapper and a test block referring to that same missing file
#
# Run:  ruby test/clawrtc_formula_test.rb
# Add the tarball check (downloads ~25 MB):
#       CLAWRTC_NETWORK_TESTS=1 ruby test/clawrtc_formula_test.rb

require "minitest/autorun"
require "digest"
require "open-uri"
require "tmpdir"

FORMULA_PATH = File.expand_path("../Formula/clawrtc.rb", __dir__)

module Kernel
  alias original_require require

  def require(path)
    return true if path == "formula"

    original_require(path)
  end
end

# Minimal stand-in for Homebrew's Pathname niceties. `bin/"clawrtc"` builds a
# fresh object every time, so writes and installs are recorded globally.
INSTALLED_FILES = []
WRITTEN_FILES = {}

class FakePath
  attr_reader :path

  def initialize(path)
    @path = path
  end

  def /(other)
    FakePath.new(File.join(@path, other.to_s))
  end

  def install(arg)
    INSTALLED_FILES << [@path, arg]
  end

  def write(content)
    WRITTEN_FILES[@path] = content
  end

  def to_s
    @path
  end

  def to_str
    @path
  end
end

# Homebrew's build ENV grows PYTHONPATH during install; record the calls.
PREPENDED_PATHS = []

def ENV.prepend_create_path(name, value)
  PREPENDED_PATHS << [name, value.to_s]
end

FakeResource = Struct.new(:name, :url, :sha256) do
  def stage(&block)
    staged << block
    block.call
  end

  def staged
    @staged ||= []
  end
end

module Language
  module Python
    def self.major_minor_version(_python)
      "3.10"
    end

    def self.setup_install_args(prefix)
      ["-c", "<setuptools shim>", "--no-user-cfg", "install", "--prefix=#{prefix}"]
    end
  end
end

class Formula
  class << self
    attr_reader :desc_value, :homepage_value, :url_value, :sha256_value,
                :version_value, :dependencies, :resource_specs, :test_block

    def desc(value)
      @desc_value = value
    end

    def homepage(value)
      @homepage_value = value
    end

    def url(value)
      @url_value = value
    end

    def version(value)
      @version_value = value
    end

    def sha256(value)
      @sha256_value = value
    end

    def depends_on(value)
      @dependencies ||= []
      @dependencies << value
    end

    def resource(name, &block)
      @resource_specs ||= []
      spec = FakeResource.new(name)
      collector = ResourceCollector.new(spec)
      collector.instance_eval(&block)
      @resource_specs << spec
    end

    def test(&block)
      @test_block = block
    end

    # The class body of a formula names the dependency formula, so "python3"
    # has to resolve during install too.
    def [](_name)
      OpenStructish.new
    end
  end

  class ResourceCollector
    def initialize(spec)
      @spec = spec
    end

    def url(value)
      @spec.url = value
    end

    def sha256(value)
      @spec.sha256 = value
    end
  end

  class OpenStructish
    def opt_bin
      FakePath.new("/usr/local/opt/python3/bin")
    end
  end

  attr_reader :libexec, :bin, :system_calls

  def initialize
    @libexec = FakePath.new("/usr/local/Cellar/clawrtc/1.6.0/libexec")
    @bin = FakePath.new("/usr/local/Cellar/clawrtc/1.6.0/bin")
    @system_calls = []
  end

  def system(*args)
    @system_calls << args.map(&:to_s)
  end

  def resources
    self.class.resource_specs || []
  end
end

load FORMULA_PATH

class ClawrtcFormulaTest < Minitest::Test
  SHA256_RE = /\A[0-9a-f]{64}\z/
  MINER_IN_TARBALL = "miners/ppc/rustchain_powerpc_g4_miner_v2.2.2.py"
  MISSING_MINER = "miners/rustchain_universal_miner.py"

  def setup
    PREPENDED_PATHS.clear
    INSTALLED_FILES.clear
    WRITTEN_FILES.clear
    @formula = Clawrtc.new
    @formula.install
  end

  def source
    @source ||= File.read(FORMULA_PATH)
  end

  def wrapper
    key = WRITTEN_FILES.keys.find { |k| k.end_with?("/bin/clawrtc") }
    refute_nil key, "the formula must write the clawrtc wrapper into bin"
    WRITTEN_FILES[key].to_s
  end

  def installed_into_libexec
    INSTALLED_FILES.select { |dest, _| dest.end_with?("/libexec") }.map(&:last)
  end

  # --- source integrity -----------------------------------------------------

  def test_sha256_is_a_real_checksum
    refute_equal "", Clawrtc.sha256_value.to_s,
                 "an empty sha256 disables integrity checking entirely"
    assert_match SHA256_RE, Clawrtc.sha256_value
  end

  def test_source_url_is_pinned_not_a_branch
    refute_includes Clawrtc.url_value, "refs/heads/",
                    "a branch tarball changes under users and cannot be checksummed"
    assert_includes Clawrtc.url_value, "refs/tags/"
  end

  # --- interpreter ----------------------------------------------------------

  def test_depends_on_python3_not_python2
    assert_includes Clawrtc.dependencies, "python3"
    refute_includes Clawrtc.dependencies, "python",
                    "Tigerbrew's python formula is 2.7.18 and cannot parse the miner"
  end

  def test_wrapper_execs_python3_by_absolute_path
    assert_match %r{exec "/usr/local/opt/python3/bin/python3"}, wrapper
    refute_match(/exec python /, wrapper)
  end

  # --- the file that never existed -----------------------------------------

  def test_installs_a_miner_that_exists_in_the_tarball
    sources = installed_into_libexec.map { |i| i.is_a?(Hash) ? i.keys.first.to_s : i.to_s }

    refute_includes sources, MISSING_MINER,
                    "that path is in no RustChain tag; Pathname#install raises Errno::ENOENT"
    assert_includes sources, MINER_IN_TARBALL
    sources.each do |path|
      refute_match %r{\Adeprecated/}, path,
                   "the deprecated miner takes no --wallet and defaults to a hardcoded node IP"
    end
  end

  def test_wrapper_runs_the_file_that_was_installed
    installed = installed_into_libexec.find { |i| i.is_a?(Hash) }
    refute_nil installed, "the miner should be installed under a stable name"
    basename = installed.values.first.to_s

    assert_includes wrapper, "/libexec/#{basename}",
                    "wrapper must run the file install actually created"
  end

  # --- vendored dependencies ------------------------------------------------

  def test_vendors_requests_and_its_install_requires
    names = resources_by_name.keys.sort
    assert_equal %w[certifi charset-normalizer idna requests urllib3], names,
                 "requests is imported at module scope; without its deps the miner cannot start"
  end

  def test_every_resource_has_a_matching_url_and_checksum
    resources_by_name.each do |name, spec|
      assert_match SHA256_RE, spec.sha256.to_s, "#{name}: sha256 must be a real digest"
      assert spec.url.to_s.end_with?(".tar.gz"), "#{name}: expected an sdist"
      basename = File.basename(spec.url.to_s).downcase.tr("_", "-")
      assert basename.start_with?("#{name.downcase.tr('_', '-')}-"),
             "#{name}: url points at #{basename}"
    end
  end

  def test_resources_are_installed_into_the_vendor_prefix
    prefixes = @formula.system_calls.map { |call| call.last }
    assert_equal resources_by_name.size, prefixes.size
    prefixes.each { |p| assert_match %r{--prefix=.*/libexec/vendor\z}, p }
  end

  def test_wrapper_exports_the_vendor_site_packages
    assert_match %r{PYTHONPATH="[^"]*/libexec/vendor/lib/python3\.10/site-packages}, wrapper,
                 "without this the miner dies on `import requests`"
  end

  def test_build_pythonpath_points_at_the_same_site_packages
    names = PREPENDED_PATHS.map(&:first)
    assert_includes names, "PYTHONPATH"

    build_path = PREPENDED_PATHS.assoc("PYTHONPATH").last
    assert_includes wrapper, build_path,
                    "resources are installed into one prefix and read from another"
  end

  # --- test block -----------------------------------------------------------

  def test_test_block_exercises_the_linked_wrapper
    body = source[/  test do\n(.*?)\n  end\n/m, 1].to_s

    assert_includes body, "bin}/clawrtc --help",
                    "brew test must run the command users get, not a bare interpreter"
    refute_includes body, "\"python\"",
                    "the old test block invoked python2 on a file that was never installed"
    assert_includes body, "--wallet",
                    "the caveats advertise --wallet; brew test should prove it exists"
  end

  def test_caveats_quick_start_flag_is_the_one_the_test_checks
    caveats = @formula.caveats
    assert_includes caveats, "clawrtc --wallet"
  end

  # --- opt-in: the real tarball --------------------------------------------

  def test_pinned_tarball_matches_checksum_and_contains_the_miner
    skip "set CLAWRTC_NETWORK_TESTS=1 to download the pinned tarball" unless ENV["CLAWRTC_NETWORK_TESTS"]

    Dir.mktmpdir do |dir|
      tarball = File.join(dir, "source.tar.gz")
      URI.parse(Clawrtc.url_value).open("rb") { |io| File.binwrite(tarball, io.read) }

      assert_equal Clawrtc.sha256_value, Digest::SHA256.file(tarball).hexdigest,
                   "formula sha256 does not match the pinned tarball"

      listing = `tar tzf #{tarball}`
      assert_match %r{/#{Regexp.escape(MINER_IN_TARBALL)}$}, listing
      refute_match %r{/#{Regexp.escape(MISSING_MINER)}$}, listing
    end
  end

  private

  def resources_by_name
    @resources_by_name ||= (Clawrtc.resource_specs || []).each_with_object({}) do |spec, acc|
      acc[spec.name] = spec
    end
  end
end
