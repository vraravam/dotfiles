# encoding: utf-8
# frozen_string_literal: true

require 'spec_helper'

RSpec.describe 'AI documentation layout' do
  let(:dotfiles_dir) { File.expand_path('..', __dir__) }
  let(:ai_dir) { File.join(dotfiles_dir, '.ai') }

  it 'gives every domain file complete frontmatter' do
    Dir.glob(File.join(ai_dir, 'domains', '*.md')).each do |path|
      content = File.read(path, encoding: 'UTF-8')
      expect(content).to start_with("---\n"), "#{path} must start with YAML frontmatter"
      end_marker = content.index("\n---\n", 3)
      expect(end_marker).not_to be_nil, "#{path} frontmatter must close with ---"
      frontmatter = content[4...end_marker]
      %w[name description applyTo].each do |key|
        expect(frontmatter).to match(/^#{key}:/), "#{path} frontmatter missing '#{key}'"
      end
    end
  end

  it 'exposes an on-demand skill for every non-always-loaded domain' do
    always_loaded = %w[edit-checklist.md whitespace-rules.md]
    Dir.glob(File.join(ai_dir, 'domains', '*.md')).each do |path|
      next if always_loaded.include?(File.basename(path))

      stem = File.basename(path, '.md')
      skill_path = File.join(dotfiles_dir, '.opencode', 'skills', "dotfiles-#{stem}", 'SKILL.md')
      expect(File.symlink?(skill_path)).to be(true), "missing skill symlink for #{stem}"
      expect(File.readable?(skill_path)).to be(true), "unreadable skill symlink for #{stem}"
    end
  end

  it 'resolves relative markdown links' do
    Dir.glob(File.join(ai_dir, '**', '*.md')).each do |path|
      File.read(path, encoding: 'UTF-8').scan(/\[[^\]]*\]\(([^)]+)\)/).flatten.each do |target|
        next if target.start_with?('http://', 'https://', 'mailto:', '#')
        next if target.include?('*')

        link_path = target.split('#').first
        next if link_path.nil? || link_path.empty?

        resolved = File.expand_path(link_path, File.dirname(path))
        expect(File.exist?(resolved)).to be(true), "broken link in #{path}: #{target}"
      end
    end
  end
end
