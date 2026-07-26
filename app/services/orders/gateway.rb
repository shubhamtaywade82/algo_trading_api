# frozen_string_literal: true

module Orders
  # Centralized broker order gateway for every tradable book.
  #
  # Responsibility:
  # - enforce the PLACE_ORDER feature toggle for all order placement paths
  # - provide a single integration point to DhanHQ order APIs
  # - route an order to the right DhanHQ surface for its asset class
  #
  # ## Books
  #
  # | asset class                          | DhanHQ surface                    | currency |
  # |--------------------------------------|-----------------------------------|----------|
  # | equity, index options, futures, comm | `Models::Order` / `SuperOrder`    | INR      |
  # | US equities                          | `Models::GlobalStocks::Order`     | USD      |
  # | multi-leg baskets (<= 15 legs)       | `Models::MultiOrder`              | INR      |
  #
  # The Global Stocks book is deliberately separate: its orders carry no
  # exchange segment, product type or validity, quantities are floats
  # (fractional shares), it adds a notional `AMOUNT` order type, and the SDK
  # does not run `Risk::Pipeline` against it because those checks resolve
  # instruments from the Indian scrip master.
  #
  # ## Safety switches
  #
  # Two independent switches must both be on for an order to reach the broker:
  #
  # - `PLACE_ORDER` — this application's gate, checked here.
  # - `LIVE_TRADING` — DhanHQ >= 2.7's own gate. The SDK raises
  #   `DhanHQ::LiveTradingDisabledError` from inside `Order#save` /
  #   `SuperOrder.create` when it is not exactly "true".
  #
  # We check the SDK's switch here as well so a misconfigured deployment gets
  # the same structured dry-run result as `PLACE_ORDER=false`, instead of an
  # exception raised from deep in the gem on the first live signal.
  #
  # ## Failed writes are never retried here
  #
  # DhanHQ >= 3.2 stopped auto-retrying order placement, modification and
  # cancellation: the API has no idempotency key, so a `POST /v2/orders` that
  # timed out may already have reached the exchange, and a retry could place a
  # second real order. Transient failures surface as `:error` results carrying
  # `reconcilable: true` — the caller must reconcile against the order book
  # (by `correlation_id`) before resubmitting. Do not add a retry here.
  #
  # ## Paper trading
  #
  # With `PAPER_TRADING=true` the domestic paths route to {Paper::Broker},
  # which fills against the live feed with a slippage assumption and persists
  # the fill as an Order row. Because the switch lives here, every caller gets
  # paper behaviour without changing code and the result shape is unchanged.
  # Paper mode intentionally bypasses PLACE_ORDER/LIVE_TRADING: nothing reaches
  # the broker, so those gates have nothing to protect.
  class Gateway
    # Asset classes that route to the domestic (INR) order API.
    DOMESTIC_ASSET_CLASSES = %i[equity index options futures currency commodity].freeze

    # Asset classes that route to the Global Stocks (USD) order API.
    GLOBAL_ASSET_CLASSES = %i[global global_equity us_equity].freeze

    class << self
      # Places an order on the book matching its asset class.
      #
      # @param payload [Hash] broker order payload
      # @param asset_class [Symbol, String, nil] see DOMESTIC_ASSET_CLASSES /
      #   GLOBAL_ASSET_CLASSES. Inferred from the payload when omitted.
      # @param logger [#info,#warn] logger-like object
      # @param source [String] caller identifier for logs
      # @return [Hash] result hash with :dry_run, :order details, or :error
      def place(payload, asset_class: nil, logger: Rails.logger, source: nil)
        resolved = (asset_class || infer_asset_class(payload)).to_sym

        if GLOBAL_ASSET_CLASSES.include?(resolved)
          place_global_order(payload, logger: logger, source: source)
        else
          place_order(payload, logger: logger, source: source)
        end
      end

      # Places a regular domestic order through the broker.
      #
      # @param payload [Hash] broker order payload
      # @param logger [#info,#warn] logger-like object
      # @param source [String] caller identifier for logs
      # @return [Hash] result hash with :dry_run or :order details
      def place_order(payload, logger: Rails.logger, source: nil)
        return Paper::Broker.place(payload, source: source) if Paper::Broker.enabled?
        return blocked_result(payload, logger: logger, source: source) unless place_order_enabled?(logger: logger, source: source)

        submit(payload, logger: logger, source: source, book: :domestic) do
          order = DhanHQ::Models::Order.new(payload)
          order.save
          order
        end
      end

      # Places a super/bracket order through the broker.
      #
      # @param payload [Hash] super-order payload
      # @param logger [#info,#warn] logger-like object
      # @param source [String] caller identifier for logs
      # @return [Hash] result hash with :dry_run or :order details
      def place_super_order(payload, logger: Rails.logger, source: nil)
        # Paper mode fills the entry leg; the SL/target legs are not simulated.
        return Paper::Broker.place(payload, source: source) if Paper::Broker.enabled?
        return blocked_result(payload, logger: logger, source: source) unless place_order_enabled?(logger: logger, source: source)

        submit(payload, logger: logger, source: source, book: :domestic) do
          DhanHQ::Models::SuperOrder.create(payload)
        end
      end

      # Places a US equity order through the Global Stocks book.
      #
      # Unlike a domestic order this payload carries no exchange segment,
      # product type or validity. `security_id` is the ticker (e.g. "AAPL"),
      # `quantity` is a Float so fractional shares work, and an `AMOUNT` order
      # type buys a notional USD value via `amount:` instead of `quantity:`.
      #
      # @param payload [Hash] global-stocks order payload
      # @param logger [#info,#warn] logger-like object
      # @param source [String] caller identifier for logs
      # @return [Hash] result hash with :dry_run or :order details
      def place_global_order(payload, logger: Rails.logger, source: nil)
        return blocked_result(payload, logger: logger, source: source) unless place_order_enabled?(logger: logger, source: source)

        submit(payload, logger: logger, source: source, book: :global) do
          DhanHQ::Models::GlobalStocks::Order.place(normalize_global_payload(payload))
        end
      end

      # Places a multi-leg basket order (max 15 legs) in one request.
      #
      # Partial acceptance is normal here, so the result reports which legs the
      # exchange took rather than a single order id.
      #
      # @param legs [Array<Hash>] per-leg order payloads
      # @param logger [#info,#warn] logger-like object
      # @param source [String] caller identifier for logs
      # @return [Hash] result hash with :dry_run, :accepted/:rejected, or :error
      def place_basket_order(legs, logger: Rails.logger, source: nil)
        return blocked_result(legs, logger: logger, source: source) unless place_order_enabled?(logger: logger, source: source)

        submit(legs, logger: logger, source: source, book: :basket) do
          DhanHQ::Models::MultiOrder.create(Array(legs))
        end
      end

      # Checks whether live order placement is enabled.
      #
      # Requires both this app's `PLACE_ORDER` toggle and the SDK's own
      # `LIVE_TRADING` toggle.
      #
      # @param logger [#warn,nil] logger-like object
      # @param source [String,nil] caller identifier for logs
      # @return [Boolean]
      def place_order_enabled?(logger: Rails.logger, source: nil)
        blocked_reason(logger: logger, source: source).nil?
      end

      # Infers which book a payload belongs to.
      #
      # A Global Stocks payload is recognised by its INX_EQ segment, or by the
      # absence of an exchange segment combined with a non-numeric (ticker)
      # security id — domestic security ids are always numeric.
      #
      # @param payload [Hash]
      # @return [Symbol]
      def infer_asset_class(payload)
        return :equity unless payload.is_a?(Hash)

        segment = (payload[:exchange_segment] || payload['exchange_segment']).to_s
        return :global if segment == DhanHQ::Constants::ExchangeSegment::INX_EQ

        security_id = (payload[:security_id] || payload['security_id']).to_s
        return :global if segment.empty? && security_id.present? && !security_id.match?(/\A\d+\z/)

        DOMESTIC_SEGMENT_CLASSES.fetch(segment, :equity)
      end

      private

      DOMESTIC_SEGMENT_CLASSES = {
        'IDX_I' => :index,
        'NSE_EQ' => :equity,
        'BSE_EQ' => :equity,
        'NSE_FNO' => :futures,
        'BSE_FNO' => :futures,
        'NSE_CURRENCY' => :currency,
        'BSE_CURRENCY' => :currency,
        'MCX_COMM' => :commodity
      }.freeze
      private_constant :DOMESTIC_SEGMENT_CLASSES

      # Runs a broker call, translating the SDK's failure modes into the
      # structured results every caller in this app already expects.
      def submit(payload, logger:, source:, book:)
        order = yield
        success_result(order, book: book)
      rescue DhanHQ::RiskViolation => e
        # 3.1+ runs Risk::Pipeline before every domestic order.
        logger&.warn("[Orders::Gateway] risk pipeline rejected order: #{e.message}#{source_suffix(source)}")
        { dry_run: false, blocked: true, risk_violation: true, message: e.message, payload: payload }
      rescue DhanHQ::LiveTradingDisabledError => e
        logger&.warn("[Orders::Gateway] SDK live-trading guard fired: #{e.message}#{source_suffix(source)}")
        { dry_run: true, blocked: true, message: e.message, payload: payload }
      rescue DhanHQ::ValidationError => e
        logger&.error("[Orders::Gateway] payload rejected by contract: #{e.message}#{source_suffix(source)}")
        { dry_run: false, error: true, message: e.message, payload: payload }
      rescue DhanHQ::NetworkError, DhanHQ::RateLimitError => e
        # The SDK no longer retries writes, and neither do we: the order may
        # already be live at the exchange. Surface it for reconciliation.
        logger&.error("[Orders::Gateway] transient failure on a write; reconcile before resubmitting: #{e.message}#{source_suffix(source)}")
        {
          dry_run: false,
          error: true,
          reconcilable: true,
          correlation_id: payload.is_a?(Hash) ? (payload[:correlation_id] || payload['correlation_id']) : nil,
          message: e.message,
          payload: payload
        }
      end

      def success_result(order, book:)
        # Some SDK paths answer with an ErrorObject rather than raising.
        return error_object_result(order, book: book) if order.is_a?(DhanHQ::ErrorObject)
        return basket_result(order) if book == :basket

        {
          dry_run: false,
          book: book,
          order_id: order.order_id || order.id,
          order_status: order.order_status || (order.respond_to?(:status) ? order.status : nil),
          raw: order
        }
      end

      def error_object_result(error_object, book:)
        message = error_object.try(:message) || error_object.try(:error_message) || error_object.inspect
        { dry_run: false, book: book, error: true, message: message, raw: error_object }
      end

      def basket_result(multi_order)
        {
          dry_run: false,
          book: :basket,
          order_ids: multi_order.order_ids,
          accepted: multi_order.accepted,
          rejected: multi_order.rejected,
          all_accepted: multi_order.all_accepted?,
          raw: multi_order
        }
      end

      # Global Stocks quantities are floats (fractional shares) and the book
      # has no exchange segment / product type / validity, so drop any that a
      # domestic-shaped caller passed through.
      def normalize_global_payload(payload)
        params = payload.to_h.symbolize_keys
        params.delete(:exchange_segment)
        params.delete(:product_type)
        params.delete(:validity)
        params[:quantity] = params[:quantity].to_f if params[:quantity]
        params[:security_id] = params[:security_id].to_s if params[:security_id]
        params
      end

      # @return [String, nil] why placement is blocked, or nil when allowed
      def blocked_reason(logger: Rails.logger, source: nil)
        if ENV['PLACE_ORDER'] != 'true'
          logger&.warn("[Orders::Gateway] PLACE_ORDER disabled; order blocked#{source_suffix(source)}")
          return 'PLACE_ORDER is not true; order not sent.'
        end

        # DhanHQ >= 2.7 refuses every order mutation without this.
        if ENV['LIVE_TRADING'] != 'true'
          logger&.warn("[Orders::Gateway] LIVE_TRADING disabled; order blocked#{source_suffix(source)}")
          return 'LIVE_TRADING is not true; DhanHQ SDK would reject this order.'
        end

        nil
      end

      def blocked_result(payload, logger:, source: nil)
        reason = blocked_reason(logger: nil, source: source) || 'order not sent.'
        logger&.info("[Orders::Gateway] blocked payload=#{payload.inspect}#{source_suffix(source)}")
        { dry_run: true, blocked: true, message: reason, payload: payload }
      end

      def source_suffix(source)
        source.present? ? " (source=#{source})" : ''
      end
    end
  end
end
