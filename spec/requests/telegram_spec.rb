require 'rails_helper'

RSpec.describe 'Telegram', type: :request do
  describe 'POST /telegram/webhook' do
    it 'returns a successful response' do
      post '/telegram/webhook'
      expect(response).to have_http_status(:ok)
    end
  end
end
