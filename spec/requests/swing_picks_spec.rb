require 'rails_helper'

RSpec.describe 'SwingPicks', type: :request do
  describe 'GET /swing_picks' do
    it 'returns a successful response' do
      get '/swing_picks'
      expect(response).to have_http_status(:success)
    end
  end
end
