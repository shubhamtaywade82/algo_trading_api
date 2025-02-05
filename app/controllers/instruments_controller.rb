# frozen_string_literal: true

class InstrumentsController < ApplicationController
  def index
    # Initialize the Ransack search object
    q = Instrument.ransack(params[:q])

    # Perform search and paginate results
    instruments = q.result.page(params[:page]).per(params[:per_page] || 20)

    render json: {
      instruments: instruments, meta: {
        current_page: instruments.current_page,
        total_pages: instruments.total_pages,
        total_count: instruments.total_count
      }
    }
  end

  def show
    instruments = Instrument.where(security_id: params[:id])
    render json: instruments
  end

  private

  def instrument_params
    params.require(:instrument).permit(:id, :symbol_name, :display_name, :exchange, :segment)
  end
end
