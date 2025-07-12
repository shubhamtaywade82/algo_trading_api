# spec/support/cache.rb
RSpec.configure do |config|
  config.before(:suite) do
    Rails.cache = ActiveSupport::Cache::MemoryStore.new
  end
  config.after { Rails.cache.clear }
end
