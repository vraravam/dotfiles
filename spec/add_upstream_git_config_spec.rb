# encoding: utf-8
# frozen_string_literal: true

require_relative '../scripts/add-upstream-git-config'

RSpec.describe AddUpstreamGitConfig do
  let(:git) { instance_double(GitProcessor) }
  let(:ok) { instance_double(Process::Status, success?: true, exitstatus: 0) }
  let(:failed) { instance_double(Process::Status, success?: false, exitstatus: 1) }
  let(:dir) { '/tmp/spec-fork' }

  before do
    Logging.state.reset!
    allow(Logging).to receive(:info)
    allow(Logging).to receive(:debug)
    allow(Logging).to receive(:success)
    allow(GitProcessor).to receive(:repo?).with(dir).and_return(true)
    allow(GitProcessor).to receive(:new).with(dir: dir).and_yield(git)
    allow(git).to receive_messages(remote_url: nil, construct_upstream_url: ['git@github.com:orig/repo.git', 'me'],
                                   add_remote: ['', '', ok], fetch_all: ['', '', ok])
  end

  after { Logging.state.reset! }

  def run_it(upstream_owner: 'orig')
    described_class.run(dir: dir, upstream_owner: upstream_owner)
  end

  it 'skips (successfully) a directory that is not a git repo' do
    allow(GitProcessor).to receive(:repo?).with(dir).and_return(false)

    expect(GitProcessor).not_to receive(:new)
    expect(run_it).to be true
  end

  it 'leaves an existing upstream remote alone' do
    allow(git).to receive(:remote_url).with(name: 'upstream').and_return('git@github.com:orig/repo.git')

    expect(git).not_to receive(:add_remote)
    expect(run_it).to be true
  end

  it 'adds and fetches the upstream remote when it is missing' do
    expect(git).to receive(:add_remote).with('upstream', 'git@github.com:orig/repo.git').and_return(['', '', ok])
    expect(git).to receive(:fetch_all).and_return(['', '', ok])

    expect(run_it).to be true
  end

  it 'does nothing when origin is already owned by the upstream owner' do
    allow(git).to receive(:construct_upstream_url).and_return(['git@github.com:orig/repo.git', 'orig'])

    expect(git).not_to receive(:add_remote)
    expect(run_it(upstream_owner: 'orig')).to be true
  end

  it 'fails when the upstream URL cannot be constructed' do
    allow(git).to receive(:construct_upstream_url).and_return([nil, nil])

    expect(git).not_to receive(:add_remote)
    expect(run_it).to be false
  end

  it 'records an error and fails when adding the remote fails' do
    allow(git).to receive(:add_remote).and_return(['', 'boom', failed])
    expect(Logging).to receive(:record_error).with(/Failed to add upstream remote/)

    expect(git).not_to receive(:fetch_all)
    expect(run_it).to be false
  end

  it 'records an error and fails when the follow-up fetch fails' do
    allow(git).to receive(:fetch_all).and_return(['', 'offline', failed])
    expect(Logging).to receive(:record_error).with(/Failed to fetch upstream remote/)

    expect(run_it).to be false
  end

  it 'accepts a Pathname for dir' do
    allow(GitProcessor).to receive(:repo?).with(dir).and_return(true)

    expect(described_class.run(dir: Pathname(dir), upstream_owner: 'orig')).to be true
  end
end
