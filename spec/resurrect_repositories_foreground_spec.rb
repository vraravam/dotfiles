# encoding: utf-8
# frozen_string_literal: true

require 'fileutils'
require 'open3'
require 'stringio'
require 'tmpdir'
require 'yaml'
require 'git_processor'
require_relative '../scripts/resurrect-repositories'

# Repositories are resurrected one at a time, in this process, in path order: each repository's
# output is one contiguous block that appears as it happens. Concurrent workers were removed because
# interleaved/replayed output was too hard to follow.
RSpec.describe ResurrectRepositories, 'sequential output' do
  let!(:tmp) { Dir.mktmpdir('resurrect-foreground-spec-') }
  let(:config) { File.join(tmp, 'repos.yml') }
  let(:success) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:events) { [] }

  around do |example|
    with_env('RR_SPEC_BASE' => File.join(tmp, 'work'), 'FIRST_INSTALL' => nil) { example.run }
  end

  before do
    Logging.state.reset!
    FileUtils.mkdir_p(File.join(tmp, 'work'))
    log = events
    allow(GitProcessor).to receive(:clone_repo_into) do |_url, dest, **_|
      name = File.basename(dest.to_s)
      log << [:start, name, Process.pid]
      puts "clone #{name}"
      log << [:end, name, Process.pid]
      true
    end
    allow_any_instance_of(GitProcessor).to receive(:fetch_all).and_return(['', '', success])
  end

  after do
    FileUtils.rm_rf(tmp)
    Logging.state.reset!
  end

  def write_config(names)
    entries = names.map { |name| { 'active' => true, 'folder' => "${RR_SPEC_BASE}/#{name}", 'remote' => "file://#{tmp}/#{name}.git" } }
    File.write(config, entries.to_yaml)
  end

  def run_resurrect
    original = $stdout
    $stdout = StringIO.new
    result = described_class.run(resurrect: config)
    [result, $stdout.string]
  ensure
    $stdout = original
  end

  it 'finishes each repository completely before starting the next, all in this process' do
    write_config(%w[a b c d])

    run_resurrect

    expect(events.map { |kind, name, _| [kind, name] }).to eq(
      [[:start, 'a'], [:end, 'a'], [:start, 'b'], [:end, 'b'], [:start, 'c'], [:end, 'c'], [:start, 'd'], [:end, 'd']]
    )
    expect(events.map(&:last).uniq).to eq([Process.pid])
  end

  it 'never forks a worker process' do
    write_config(%w[a b c])
    expect(Process).not_to receive(:fork)
    expect(Kernel).not_to receive(:fork)

    run_resurrect
  end

  it 'prints one block per repository, in path order, with its output between its own header and the next' do
    write_config(%w[a b c])

    _result, output = run_resurrect

    positions = %w[a b c].map { |name| output.index("clone #{name}") }
    expect(positions).to all(be_a(Integer))
    expect(positions).to eq(positions.sort)
  end

  it 'no longer offers a job count' do
    expect(described_class.method(:run).parameters.map(&:last)).not_to include(:jobs)
    expect(described_class.constants).not_to include(:DEFAULT_JOBS, :MAX_JOBS, :DEFAULT_REPO_TIMEOUT)
  end
end
