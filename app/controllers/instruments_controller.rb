class InstrumentsController < ApplicationController
  def index
    # Initialize the Ransack search object
    q = Instrument.ransack(params[:q])

    instruments = Instrument.all.page(params[:page]).per(params[:per_page] || 20)

    # Perform search and paginate results
    instruments = q.result.page(params[:page]).per(params[:per_page] || 20)

    render json: {
      instruments:,
      meta: {
        current_page: instruments.current_page,
        total_pages: instruments.total_pages,
        total_count: instruments.total_count
      }
    }
  end

  def show
    instrument = Instrument.find(params[:id])
    render json: instrument
  end

  private

  def instrument_params
    params.require(:instrument).permit(:id, :symbol_name, :display_name, :exchange, :segment)
  end
end
