# encoding: utf-8
# frozen_string_literal: true

require 'tmpdir'
require_relative '../scripts/software-updates-cron'

RSpec.describe SoftwareUpdatesCron do
  around do |example|
    Dir.mktmpdir('software-updates-spec-') do |dir|
      @tmp = Pathname(dir)
      example.run
    end
  end

  before do
    Logging.state.reset!
    %i[info success debug warn].each { |level| allow(Logging).to receive(level) }
    allow(Logging).to receive(:section_header)
    stub_const('EnvVars::DOWNLOADS', @tmp)
    stub_const('EnvVars::XDG_CACHE_HOME', @tmp.join('cache'))
    stub_const('EnvVars::PROJECTS_BASE_DIR', @tmp.join('dev'))
    described_class.instance_variable_set(:@steps, StepCounter.new(20))
  end

  after do
    described_class.remove_instance_variable(:@steps) if described_class.instance_variable_defined?(:@steps)
    Logging.state.reset!
  end

  describe '.run' do
    before do
      allow(described_class).to receive(:_run_all_updates).and_return('')
      allow(MacOS).to receive(:notify)
    end

    let(:run_log) { @tmp.join('software-updates-run-log') }

    it 'succeeds, notifies with a check mark and appends the completion marker when nothing went wrong' do
      expect(MacOS).to receive(:notify).with(/Done at .* \(took .*\)\./, "\u2705 Software Updates")

      expect(described_class.run(start_time: Time.now.to_i)).to be true
      expect(run_log.read).to match(/\ACOMPLETED: .* \(took .*\)\n\z/)
    end

    it 'fails, lists the recorded issues in the notification and writes no completion marker' do
      allow(Logging).to receive(:record_warning).and_call_original
      Logging.record_warning('brew was slow')
      expect(MacOS).to receive(:notify).with(/1 warning\(s\): .*brew was slow/, "\u26A0\uFE0F Software Updates")

      expect(described_class.run(start_time: Time.now.to_i)).to be false
      expect(run_log).not_to exist
    end

    it 'flags greedy apps that need a manual update, yet still counts the run as successful' do
      allow(described_class).to receive(:_run_all_updates).and_return('Firefox, Zoom')
      expect(MacOS).to receive(:notify).with(/Needs manual update: Firefox, Zoom/, "\u26A0\uFE0F Software Updates")

      expect(described_class.run(start_time: Time.now.to_i)).to be true
    end

    it 'appends the completion marker to what the start marker already wrote' do
      run_log.write("STARTED: earlier\n")

      described_class.run(start_time: Time.now.to_i)

      expect(run_log.readlines.map(&:chomp)).to match(['STARTED: earlier', /\ACOMPLETED: /])
    end
  end

  describe '._perform_update' do
    def perform(title = 'thing', command = 'thing-cmd', &block)
      described_class.send(:_perform_update, title, command, &block)
    end

    it 'does not run the block when the command is not installed' do
      allow(PathUtils).to receive(:command_exists?).with('thing-cmd').and_return(false)

      expect { |probe| perform(&probe) }.not_to yield_control
      expect(Logging.warnings?).to be false
    end

    it 'reports success when the block returns truthy' do
      allow(PathUtils).to receive(:command_exists?).with('thing-cmd').and_return(true)
      expect(Logging).to receive(:success).with(/Successfully updated.*thing/)

      perform { true }

      expect(Logging.warnings?).to be false
    end

    it 'records a warning, rather than raising, when the block returns falsey' do
      allow(PathUtils).to receive(:command_exists?).with('thing-cmd').and_return(true)
      allow(Logging).to receive(:record_warning).and_call_original

      perform { false }

      expect(Logging.step_warnings.first).to match(/Failed to update 'thing'/)
    end

    it 'numbers each update as its own step' do
      allow(PathUtils).to receive(:command_exists?).and_return(false)
      titles = []
      allow(Logging).to receive(:with_step) { |title, *| titles << title }

      perform('one', 'a')
      perform('two', 'b')

      expect(titles).to match([/Step 1 of 20.*update one/, /Step 2 of 20.*update two/])
    end
  end

  describe '._run_if_due' do
    let(:cache_file) { @tmp.join('last-update') }

    it 'runs the block, and stamps the cache file, when no cache file exists yet' do
      ran = false

      expect(described_class.send(:_run_if_due, cache_file, 3600, 'things') { ran = true }).to be true
      expect(ran).to be true
      expect(cache_file).to exist
    end

    it 'skips the block, with a debug message, while the interval has not elapsed' do
      cache_file.write('')
      expect(Logging).to receive(:debug).with(/things.*updated.*hour\(s\) ago -- skipping/)

      expect { |probe| described_class.send(:_run_if_due, cache_file, 3600, 'things', &probe) }.not_to yield_control
    end

    it 'runs the block again once the interval has elapsed' do
      cache_file.write('')
      File.utime(Time.now - 7200, Time.now - 7200, cache_file)

      expect { |probe| described_class.send(:_run_if_due, cache_file, 3600, 'things', &probe) }.to yield_control
    end

    it 'returns false when skipped' do
      cache_file.write('')

      expect(described_class.send(:_run_if_due, cache_file, 3600, 'things') { nil }).to be false
    end
  end

  describe '._update_home_repos' do
    it 'rebases the repos under HOME that match the config/zsh/mise filter' do
      expect(RunAll).to receive(:run).with(command: %w[git fo --rebase], folder: EnvVars::HOME.to_s,
                                           filter: '.config|zsh|mise', maxdepth: 5).and_return(true)

      described_class.send(:_update_home_repos)

      expect(Logging.warnings?).to be false
    end

    it 'records a warning when some repos could not be updated' do
      allow(RunAll).to receive(:run).and_return(false)
      allow(Logging).to receive(:record_warning).and_call_original

      described_class.send(:_update_home_repos)

      expect(Logging.step_warnings.first).to match(/home repos could not be auto-updated/)
    end
  end

  describe '._upreb_oss_repos' do
    it 'does nothing when the oss folder does not exist' do
      expect(RunAll).not_to receive(:run)

      described_class.send(:_upreb_oss_repos)
    end

    it 'runs "git upreb" over the oss folder' do
      @tmp.join('dev', 'oss').mkpath
      expect(RunAll).to receive(:run).with(command: %w[git upreb], folder: @tmp.join('dev', 'oss').to_s,
                                           maxdepth: 4).and_return(true)

      described_class.send(:_upreb_oss_repos)

      expect(Logging.warnings?).to be false
    end

    it 'records a warning when some repos could not be updated' do
      @tmp.join('dev', 'oss').mkpath
      allow(RunAll).to receive(:run).and_return(false)
      allow(Logging).to receive(:record_warning).and_call_original

      described_class.send(:_upreb_oss_repos)

      expect(Logging.step_warnings.first).to match(/oss repos could not be auto-updated/)
    end
  end
end
