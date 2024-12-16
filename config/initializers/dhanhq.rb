require "dhanhq"

Dhanhq.configure do |config|
  config.client_id = ENV["DHAN_CLIENT_ID"]
  config.access_token = ENV["DHAN_ACCESS_TOKEN"]
end
