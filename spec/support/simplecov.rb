require 'simplecov'

SimpleCov.start 'rails' do
  enable_coverage :branch        # line + branch coverage
  # Current suite coverage is ~35% line coverage. Default to a realistic
  # baseline while still allowing local/CI overrides.
  minimum_coverage ENV.fetch('SIMPLECOV_MIN_COVERAGE', 30).to_i
  maximum_coverage_drop ENV.fetch('SIMPLECOV_MAXIMUM_COVERAGE_DROP', 1.0).to_f # allow override for local runs
  add_filter %w[/spec/ /config/] # ignore test & config files

  add_group 'Services',     'app/services'
  add_group 'Interactors',  'app/interactors'
  add_group 'Serializers',  'app/serializers'
end

puts 'SimpleCov started…' if SimpleCov.running