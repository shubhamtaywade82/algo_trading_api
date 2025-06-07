module Openai
  class MessagesController < ApplicationController
    def create
      prompt = params[:prompt]
      system = params[:system]
      model = params[:model]

      result = Openai::MessageProcessor.call(prompt, model: model, system: system)
      render json: { result: result }
    end
  end
end
