# frozen_string_literal: true

# Ruby reads files in the environment's default external encoding, which is US-ASCII under
# cron: a UTF-8 file then raises "invalid byte sequence in US-ASCII". Every file read in the
# scripts must therefore name its encoding (Pathname#read(encoding: 'UTF-8')) or go through
# Core.read_lines_utf8 / Core.each_line_utf8. This spec keeps new code from regressing.
RSpec.describe 'UTF-8 file reads' do
  # Calls that read a file's contents (a bare `.read`, `.readlines`, `File.foreach`, ...).
  let(:risky_read) { /\.readlines\b|\bFile\.(read|foreach)\b|\bIO\.(read|readlines|foreach)\b|\.read\b|YAML\.(load_file|safe_load_file)/ }

  # Reads that are never file reads (streams) or are the helper's own implementation.
  let(:allowed) { [/\$stdin\.read/, /file\.each_line\(&block\)/] }

  def risky_lines(path)
    File.read(path, encoding: 'UTF-8').each_line.with_index(1).map do |line, number|
      next if line.strip.start_with?('#') || line.include?('encoding:')
      next if allowed.any? { |pattern| line.match?(pattern) }
      next unless line.match?(risky_read)

      "#{path.sub("#{Dir.pwd}/", '')}:#{number}: #{line.strip}"
    end.compact
  end

  it 'never reads a file without an explicit encoding' do
    offenders = Dir[File.expand_path('../scripts/**/*.rb', __dir__)].flat_map { |path| risky_lines(path) }

    expect(offenders).to be_empty, "file reads without encoding: 'UTF-8':\n#{offenders.join("\n")}"
  end
end
