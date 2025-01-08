require "rails_helper"

RSpec.describe Webhooks::AlertsController, type: :controller do
  describe "POST #create" do
    let!(:instrument) { create(:instrument) }
    let!(:derivative) { create(:derivative, instrument: instrument) }
    let!(:margin_requirement) { create(:margin_requirement, instrument: instrument) }
    let!(:mis_detail) { create(:mis_detail, instrument: instrument) }
    let!(:order_feature) { create(:order_feature, instrument: instrument) }
    let(:valid_alert) { attributes_for(:alert) }

    context "when a valid stock alert is received" do
      it "creates the alert and processes it" do
        expect {
          post :create, params: { alert: valid_alert }
        }.to change(Alert, :count).by(1)

        expect(response).to have_http_status(:ok)
        expect(JSON.parse(response.body)["message"]).to eq("Alert processed successfully")
      end
    end

    context "when a valid index alert is received" do
      let(:valid_index_alert) do
        attributes_for(:alert, ticker: "NIFTY", instrument_type: "index", strategy_id: "NIFTY_intraday")
      end

      it "creates the alert and processes it with option chain analysis" do
        post :create, params: { alert: valid_index_alert }

        alert = Alert.last
        expect(alert.instrument_type).to eq("index")
        expect(alert.strategy_id).to eq("NIFTY_intraday")
        expect(response).to have_http_status(:ok)
      end
    end

    context "when the alert payload is invalid" do
      it "returns an error and does not save the alert" do
        post :create, params: { alert: valid_alert.except(:ticker) }

        expect(response).to have_http_status(:unprocessable_entity)
        expect(Alert.count).to eq(0)
        expect(JSON.parse(response.body)["error"]).to eq("Invalid or delayed alert")
      end
    end

    context "when processing fails" do
      before do
        allow(AlertProcessor).to receive(:call).and_raise(StandardError.new("Processing error"))
      end

      it "updates the alert status to failed" do
        post :create, params: { alert: valid_alert }

        alert = Alert.last
        expect(alert.status).to eq("failed")
        expect(alert.error_message).to eq("Processing error")
      end
    end
  end
end
