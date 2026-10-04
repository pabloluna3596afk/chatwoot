# Rubocop on the Ruby files a change touches, reporting only the offences on the lines the change adds or edits.
# Whole files are not held to the standard: some of them (the Google Calendar service, the Captain assistant) carry
# offences that predate any change and are not the change's to fix. Usage: ruby rubocop_changed_lines.rb [base-ref]
require 'json'
require 'open3'

base = ARGV.fetch(0, 'origin/develop')

files, = Open3.capture2('git', 'diff', '--name-only', '--diff-filter=d', "#{base}...HEAD", '--', '*.rb')
files = files.split("\n")
if files.empty?
  puts 'No Ruby files changed.'
  exit 0
end

# { 'path' => [changed line numbers] } from the zero-context diff.
changed = Hash.new { |hash, key| hash[key] = [] }
diff, = Open3.capture2('git', 'diff', '-U0', "#{base}...HEAD", '--', '*.rb')
current = nil
diff.each_line do |line|
  if line.start_with?('+++ b/')
    current = line.delete_prefix('+++ b/').strip
  elsif (match = line.match(/\A@@ -\d+(?:,\d+)? \+(\d+)(?:,(\d+))? @@/)) && current
    start = match[1].to_i
    count = match[2] ? match[2].to_i : 1
    changed[current].concat((start...(start + count)).to_a)
  end
end

output, = Open3.capture2('bundle', 'exec', 'rubocop', '--force-exclusion', '--format', 'json', *files)
report = JSON.parse(output)

offences = report['files'].flat_map do |file|
  file['offenses'].filter_map do |offence|
    next unless changed[file['path']].include?(offence['location']['start_line'])

    "#{file['path']}:#{offence['location']['start_line']}:#{offence['location']['start_column']}: " \
      "#{offence['cop_name']}: #{offence['message']}"
  end
end

if offences.empty?
  puts "Rubocop: no offences on the changed lines of #{files.size} files."
else
  puts offences
  puts "Rubocop: #{offences.size} offence(s) on changed lines."
  exit 1
end
