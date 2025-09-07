class SwingPicksController < ApplicationController
  def index
    render json: { message: 'Swing picks endpoint' }
  end
end
