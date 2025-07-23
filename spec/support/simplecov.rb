require 'simplecov'

SimpleCov.start 'rails' do
  enable_coverage :branch        # line + branch coverage
  minimum_coverage 90            # fail build if < 90 %
  maximum_coverage_drop 1.0      # max 1 % drop per PR
  add_filter %w[/spec/ /config/] # ignore test & config files

  add_group 'Services',     'app/services'
  add_group 'Interactors',  'app/interactors'
  add_group 'Serializers',  'app/serializers'
end

puts 'SimpleCov started…' if SimpleCov.running