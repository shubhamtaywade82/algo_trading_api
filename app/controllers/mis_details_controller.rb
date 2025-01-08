class MisDetailsController < ApplicationController
  def index
    # Use Ransack for searching
    search = MisDetail.includes(:instrument).ransack(params[:q])
    mis_details = search.result.page(params[:page]).per(params[:per_page] || 10)

    # Prepare the response with associated instrument details
    render json: {
      mis_details: mis_details.as_json(include: {
        instrument: {
          only: %i[id symbol_name display_name exchange segment instrument_type]
        }
      }),
      meta: {
        current_page: mis_details.current_page,
        total_pages: mis_details.total_pages,
        total_count: mis_details.total_count
      }
    }
  end

  def show
    mis_detail = MisDetail.find(params[:id])
    render json: mis_detail
  end

  def create
    mis_detail = MisDetail.new(mis_detail_params)
    if mis_detail.save
      render json: mis_detail, status: :created
    else
      render json: mis_detail.errors, status: :unprocessable_entity
    end
  end

  def update
    mis_detail = MisDetail.find(params[:id])
    if mis_detail.update(mis_detail_params)
      render json: mis_detail
    else
      render json: mis_detail.errors, status: :unprocessable_entity
    end
  end

  def destroy
    mis_detail = MisDetail.find(params[:id])
    mis_detail.destroy
    head :no_content
  end

  private

  def mis_detail_params
    params.require(:mis_detail).permit(:mis_leverage, :co_leverage, :bo_leverage, :instrument_id)
  end
end
