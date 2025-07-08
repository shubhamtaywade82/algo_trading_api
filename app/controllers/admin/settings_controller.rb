class Admin::SettingsController < ApplicationController
  # http_basic_authenticate_with name: ENV.fetch('ADMIN_USER', nil), password: ENV.fetch('ADMIN_PASS', nil) # or devise, pundit, etc.

  def index
    render json: AppSetting.all.order(:key)
  end

  def update
    AppSetting[params[:key]] = params.require(:value)
    Rails.cache.delete_matched("setting:#{params[:key]}*") # bust cache
    head :no_content
  end
end