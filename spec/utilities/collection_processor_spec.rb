# frozen_string_literal: true

require 'collection_processor'

RSpec.describe CollectionProcessor do
  before { Logging.state.reset! }
  after { Logging.state.reset! }

  around do |example|
    with_env('_DOTFILES_SCRIPT_DEPTH' => '1', 'DIRENV_IN_ENVRC' => nil, 'LOG_LEVEL' => nil) { example.run }
  end

  def process(items, **opts, &block)
    result = nil
    expect { result = described_class.process_items(items, **opts, &block) }.to output.to_stdout
    result
  end

  describe '.process_items' do
    it 'reports successes and failures by display name' do
      result = process(%w[a b c]) { |item, _idx, _total| item != 'b' }

      expect(result).to eq(total: 3, successful: %w[a c], failed: %w[b], skipped: 0)
      expect(Logging.step_warnings.last).to match(/Processing failed for/)
    end

    it 'passes the 1-based index and the total to the block' do
      seen = []
      process(%w[a b]) { |_item, idx, total| seen << [idx, total] }

      expect(seen).to eq([[1, 2], [2, 2]])
    end

    it 'skips items matching skip_proc and excludes them from the total' do
      result = process(%w[keep skip keep2], skip_proc: ->(item) { item == 'skip' }) { true }

      expect(result).to eq(total: 2, successful: %w[keep keep2], failed: [], skipped: 1)
    end

    it 'records an error and carries on when the block raises' do
      result = process(%w[a b]) do |item|
        raise 'kaboom' if item == 'a'

        true
      end

      expect(result[:failed]).to eq(%w[a])
      expect(result[:successful]).to eq(%w[b])
      expect(Logging.step_errors.last).to match(/Exception processing .*kaboom/)
    end

    it 'does not run the block in dry-run mode but counts the items as successful' do
      ran = false
      result = process(%w[a b], dry_run: true) { ran = true }

      expect(ran).to be false
      expect(result[:successful]).to eq(%w[a b])
    end

    it 'uses item_name_proc to name items' do
      result = process([{ 'folder' => '/x' }], item_name_proc: ->(repo) { repo['folder'] }) { true }

      expect(result[:successful]).to eq(['/x'])
    end

    it 'restores the script depth it changed' do
      process(%w[a b]) { true }

      expect(EnvVars.script_depth).to eq(1)
    end

    it 'right-aligns the progress counter to the width of the total' do
      expect { described_class.process_items((1..10).to_a) { true } }.to output(/\[ 1 of 10\]/).to_stdout
    end
  end
end
