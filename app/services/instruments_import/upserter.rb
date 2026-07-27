# frozen_string_literal: true

module InstrumentsImport
  # Batch upserts one scrip-master parse into the four tables that own it.
  #
  # Every table conflicts on the same natural key the master itself is keyed by
  # — (security_id, symbol_name, exchange, segment) — so re-running an import
  # is idempotent.
  class Upserter < ApplicationService
    BATCH_SIZE = 1_000

    # `active` and `last_seen_at` are refreshed on every row the feed still
    # lists, which is what lets the staleness sweep find the ones it does not.
    SHARED_UPDATE_COLUMNS = %i[
      display_name isin instrument_code instrument_type underlying_symbol
      underlying_security_id series lot_size tick_size active last_seen_at updated_at
    ].freeze

    DERIVATIVE_UPDATE_COLUMNS = (SHARED_UPDATE_COLUMNS + %i[
      expiry_date strike_price option_type expiry_flag instrument_id
    ]).freeze

    def initialize(instruments_rows:, derivatives_rows:, order_features_rows: [], margin_requirements_rows: [])
      @instruments_rows = instruments_rows
      @derivatives_rows = derivatives_rows
      @order_features_rows = order_features_rows
      @margin_requirements_rows = margin_requirements_rows
    end

    def call
      instrument_result = import_instruments!
      derivative_result = import_derivatives!
      satellites = import_satellites!

      {
        instrument_upserts: instrument_result&.ids&.size.to_i,
        derivative_upserts: derivative_result&.ids&.size.to_i
      }.merge(satellites)
    end

    private

    def import_instruments!
      return nil if @instruments_rows.empty?

      Instrument.import(
        @instruments_rows,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: SHARED_UPDATE_COLUMNS
        }
      )
    end

    def import_derivatives!
      return nil if @derivatives_rows.empty?

      # instrument_id is nullable now, so a contract whose underlying is not in
      # the master is stored unparented rather than discarded. Only ids that do
      # not resolve are cleared, which keeps the FK honest without losing rows.
      #
      # The key is written on every row, not just the ones being cleared:
      # activerecord-import requires every hash in a batch to carry the same
      # keys, and Mapper only sets :instrument_id on the contracts whose
      # underlying it resolved. Importing its two halves as one batch — which
      # is what makes an unparented contract importable at all — raised
      # "Hash key mismatch. ... Missing keys: [:instrument_id]" on the first
      # real scrip master, where both halves are non-empty.
      valid_ids = Instrument.where(id: @derivatives_rows.filter_map { |r| r[:instrument_id] }.uniq)
        .pluck(:id).to_set
      @derivatives_rows.each do |row|
        row[:instrument_id] = nil unless valid_ids.include?(row[:instrument_id])
      end

      Derivative.import(
        @derivatives_rows,
        batch_size: BATCH_SIZE,
        on_duplicate_key_update: {
          conflict_target: %i[security_id symbol_name exchange segment],
          columns: DERIVATIVE_UPDATE_COLUMNS
        }
      )
    end

    # Satellites arrive keyed by their owner's natural key; the owners only
    # acquire ids in the two imports above, so resolve them here.
    def import_satellites!
      owner_ids = build_owner_id_index
      {
        order_feature_upserts: import_order_features!(owner_ids),
        margin_requirement_upserts: import_margin_requirements!(owner_ids)
      }
    end

    def build_owner_id_index
      index = {}
      { 'Instrument' => Instrument, 'Derivative' => Derivative }.each do |type, klass|
        # `exchange` and `segment` are enums, so pluck yields the *keys*
        # ("nse", "currency") while the parser keys satellites on the scrip
        # master's own values ("NSE", "C"). Map back before comparing.
        exchanges = klass.exchanges
        segments = klass.segments

        klass.pluck(:id, :security_id, :symbol_name, :exchange, :segment).each do |id, sid, name, exch, seg|
          key = [sid.to_s, name.to_s,
                 exchanges.fetch(exch.to_s, exch.to_s),
                 segments.fetch(seg.to_s, seg.to_s)]
          index[[type, key]] = id
        end
      end
      index
    end

    def import_order_features!(owner_ids)
      rows = resolve_owners(@order_features_rows, owner_ids, :featureable_type, :featureable_id)
      return 0 if rows.empty?

      OrderFeature.import(
        rows,
        batch_size: BATCH_SIZE,
        validate: false,
        on_duplicate_key_update: {
          conflict_target: %i[featureable_type featureable_id],
          columns: %i[bracket_flag cover_flag buy_sell_indicator asm_gsm_flag
                      asm_gsm_category mtf_leverage updated_at]
        }
      ).ids.size
    end

    def import_margin_requirements!(owner_ids)
      rows = resolve_owners(@margin_requirements_rows, owner_ids, :requirementable_type, :requirementable_id)
      return 0 if rows.empty?

      MarginRequirement.import(
        rows,
        batch_size: BATCH_SIZE,
        validate: false,
        on_duplicate_key_update: {
          conflict_target: %i[requirementable_type requirementable_id],
          columns: Parser::MARGIN_COLUMNS.values + %i[updated_at]
        }
      ).ids.size
    end

    def resolve_owners(rows, owner_ids, type_column, id_column)
      now = Time.current
      rows.filter_map do |row|
        attrs = row.except(:owner_type, :owner_key)
        owner_id = owner_ids[[row[:owner_type], row[:owner_key]]]
        next if owner_id.nil?

        attrs.merge(
          type_column => row[:owner_type],
          id_column => owner_id,
          :created_at => now,
          :updated_at => now
        )
      end
    end
  end
end
