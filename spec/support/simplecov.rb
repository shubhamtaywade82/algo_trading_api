require 'simplecov'

SimpleCov.start 'rails' do
  enable_coverage :branch        # line + branch coverage
  minimum_coverage ENV.fetch('SIMPLECOV_MIN_COVERAGE', 90).to_i # allow override for local dev
  maximum_coverage_drop ENV.fetch('SIMPLECOV_MAXIMUM_COVERAGE_DROP', 1.0).to_f # allow override for local runs
  add_filter %w[/spec/ /config/] # ignore test & config files

  add_group 'Services',     'app/services'
  add_group 'Interactors',  'app/interactors'
  add_group 'Serializers',  'app/serializers'
end

puts 'SimpleCov started…' if SimpleCov.running