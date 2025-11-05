# frozen_string_literal: true

module Dhanhq
  # Backwards-compatible facade that exposes the legacy `Dhanhq::API`
  # surface while delegating to the new `DhanHQ` gem.
  module API
    # Shared helpers for normalising payloads and wrapping model responses.
    module Helpers
      module_function

      def wrap_attributes(record)
        case record
        when nil
          {}.with_indifferent_access
        when ActiveSupport::HashWithIndifferentAccess
          record.deep_dup
        when Hash
          record.deep_dup.with_indifferent_access
        when DhanHQ::ErrorObject
          record.errors.deep_dup.with_indifferent_access
        else
          attrs =
            if record.respond_to?(:attributes)
              record.attributes
            elsif record.respond_to?(:to_h)
              record.to_h
            else
              {}
            end
          attrs = attrs.deep_dup if attrs.respond_to?(:deep_dup)
          attrs.with_indifferent_access
        end
      end

      def wrap_collection(records)
        Array(records).map { |record| wrap_attributes(record) }
      end

      def normalize_payload(payload)
        return {} if payload.blank?

        payload.each_with_object({}) do |(segment, ids), memo|
          next if ids.blank?

          memo[segment.to_s] = Array(ids).compact.map do |id|
            id.respond_to?(:to_i) ? id.to_i : id
          end
        end
      end

      def underscore_params(params)
        params.each_with_object({}) do |(key, value), memo|
          memo[key.to_s.underscore.to_sym] = value
        end
      end

      def ensure_status(hash, status = 'success')
        hash[:status] ||= status
        hash['status'] ||= status
        hash
      end

    end

    module Funds
      extend self

      def balance
        funds = DhanHQ::Models::Funds.fetch
        attrs = Helpers.wrap_attributes(funds)

        available = attrs[:availabelBalance] ||
                    attrs[:availabel_balance] ||
                    attrs[:available_balance]

        attrs[:availabelBalance] = available
        attrs['availabelBalance'] = available
        attrs[:availableBalance] ||= available
        attrs['availableBalance'] ||= available

        Helpers.ensure_status(attrs)
      end
    end

    module Holdings
      extend self

      def fetch
        Helpers.wrap_collection(DhanHQ::Models::Holding.all)
      rescue DhanHQ::NoHoldingsError
        []
      end
    end

    module Portfolio
      extend self

      def holdings
        Holdings.fetch
      end

      def positions
        Helpers.wrap_collection(DhanHQ::Models::Position.all)
      end
    end

    module MarketFeed
      extend self

      %i[ltp ohlc quote].each do |method_name|
        define_method(method_name) do |payload|
          response = DhanHQ::Models::MarketFeed.public_send(
            method_name,
            Helpers.normalize_payload(payload)
          )
          wrap_market_response(response)
        end
      end

      def wrap_market_response(response)
        return {}.with_indifferent_access unless response.is_a?(Hash)

        wrapped = response.with_indifferent_access
        data = wrapped[:data]
        if data.is_a?(Hash)
          data.each do |segment, instruments|
            next unless instruments.is_a?(Hash)

            instruments.each do |sec_id, sec_data|
              instruments[sec_id] = Helpers.wrap_attributes(sec_data)
            end
            data[segment] = instruments.with_indifferent_access
          end
        end
        wrapped
      end
      private :wrap_market_response
    end

    module Market
      extend self

      def bulk_quote(securityIds:, segment: nil, segments: nil)
        payload =
          if segments.present?
            Helpers.normalize_payload(segments)
          elsif securityIds.is_a?(Hash)
            Helpers.normalize_payload(securityIds)
          else
            { (segment || 'NSE_EQ').to_s => Array(securityIds).map { |id| id.to_i } }
          end

        response = DhanHQ::Models::MarketFeed.quote(payload)
        data = response[:data] || {}

        quotes = data.each_with_object({}) do |(_segment, instruments), memo|
          next unless instruments.is_a?(Hash)

          instruments.each do |sec_id, sec_data|
            sec_attrs = Helpers.wrap_attributes(sec_data)
            last_price = sec_attrs[:last_price] || sec_attrs[:lastPrice]
            memo[sec_id.to_s] = {
              'lastPrice' => last_price,
              'last_price' => last_price,
              lastPrice: last_price,
              ltp: last_price,
              'ltp' => last_price
            }.with_indifferent_access
          end
        end

        quotes.with_indifferent_access
      end
    end

    module Orders
      extend self

      def place(params)
        order = DhanHQ::Models::Order.place(params)
        wrap_order(order)
      end

      def modify(order_id, params)
        order = DhanHQ::Models::Order.find(order_id)
        raise "Order #{order_id} not found" unless order

        result = order.modify(params)
        return Helpers.wrap_attributes(result) if result.is_a?(DhanHQ::ErrorObject)

        wrap_order(order.refresh || order)
      end

      def list
        Helpers.wrap_collection(DhanHQ::Models::Order.all)
      end

      def cancel(order_id)
        order = DhanHQ::Models::Order.find(order_id)
        return false unless order

        order.cancel
      end

      def wrap_order(order)
        attrs = Helpers.wrap_attributes(order)
        attrs['orderId'] ||= attrs[:order_id]
        attrs[:orderId] ||= attrs[:order_id]
        attrs['orderStatus'] ||= attrs[:order_status]
        attrs[:orderStatus] ||= attrs[:order_status]
        Helpers.ensure_status(attrs) if attrs.present?
        attrs
      end
      private :wrap_order
    end

    module Historical
      extend self

      def daily(params)
        normalized = Helpers.underscore_params(params)
        response = DhanHQ::Models::HistoricalData.daily(normalized)
        Helpers.wrap_attributes(response)
      end

      def intraday(params)
        normalized = Helpers.underscore_params(params)
        response = DhanHQ::Models::HistoricalData.intraday(normalized)
        Helpers.wrap_attributes(response)
      end
    end

    module Statements
      extend self

      def ledger(from_date:, to_date:)
        Helpers.wrap_collection(
          DhanHQ::Models::LedgerEntry.all(
            from_date: from_date,
            to_date: to_date
          )
        )
      end

      def trade_history(from_date:, to_date:, page: 0)
        Helpers.wrap_collection(
          DhanHQ::Models::Trade.history(
            from_date: from_date,
            to_date: to_date,
            page: page
          )
        )
      end
    end

    module EDIS
      extend self

      def status(isin:)
        Helpers.wrap_attributes(DhanHQ::Models::Edis.inquire(isin))
      end

      def mark(params)
        params = params.with_indifferent_access
        payload = {
          isin: params[:isin],
          qty: params[:qty],
          exchange: params[:exchange],
          segment: params[:segment],
          bulk: params.fetch(:bulk, true)
        }.compact

        if payload[:bulk]
          DhanHQ::Models::Edis.bulk_form(payload)
        else
          DhanHQ::Models::Edis.form(payload)
        end

        true
      end

      def tpin
        DhanHQ::Models::Edis.tpin
      end
    end
  end

  # Proxy legacy constants module to the new namespace.
  module Constants
    DhanHQ::Constants.constants.each do |const_name|
      const_set(const_name, DhanHQ::Constants.const_get(const_name))
    end

    module_function

    def respond_to_missing?(name, include_private = false)
      DhanHQ::Constants.respond_to?(name, include_private) || super
    end

    def method_missing(name, *args, &block)
      if DhanHQ::Constants.respond_to?(name)
        DhanHQ::Constants.public_send(name, *args, &block)
      else
        super
      end
    end
  end
end
