# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.0].define(version: 2025_05_12_085023) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "alerts", force: :cascade do |t|
    t.string "ticker", null: false
    t.string "instrument_type", null: false
    t.string "order_type", null: false
    t.string "current_position"
    t.string "previous_position"
    t.decimal "current_price", precision: 15, scale: 2, null: false
    t.datetime "time", null: false
    t.string "chart_interval"
    t.string "strategy_name", null: false
    t.string "strategy_id", null: false
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.string "action"
    t.string "exchange"
    t.string "strategy_type"
    t.bigint "instrument_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "signal_type"
    t.jsonb "metadata"
    t.index ["instrument_id"], name: "index_alerts_on_instrument_id"
    t.index ["instrument_type"], name: "index_alerts_on_instrument_type"
    t.index ["strategy_id"], name: "index_alerts_on_strategy_id"
    t.index ["ticker"], name: "index_alerts_on_ticker"
  end

  create_table "delayed_jobs", force: :cascade do |t|
    t.integer "priority", default: 0, null: false
    t.integer "attempts", default: 0, null: false
    t.text "handler", null: false
    t.text "last_error"
    t.datetime "run_at"
    t.datetime "locked_at"
    t.datetime "failed_at"
    t.string "locked_by"
    t.string "queue"
    t.datetime "created_at"
    t.datetime "updated_at"
    t.index ["priority", "run_at"], name: "delayed_jobs_priority"
  end

  create_table "derivatives", force: :cascade do |t|
    t.bigint "instrument_id", null: false
    t.string "exchange", null: false
    t.string "segment", null: false
    t.string "security_id", null: false
    t.string "symbol_name", null: false
    t.string "display_name"
    t.string "instrument"
    t.string "instrument_type"
    t.string "underlying_security_id"
    t.string "underlying_symbol"
    t.date "expiry_date"
    t.decimal "strike_price", precision: 15, scale: 5
    t.string "option_type"
    t.integer "lot_size"
    t.string "expiry_flag"
    t.decimal "tick_size", precision: 10, scale: 5
    t.boolean "asm_gsm_flag", default: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument_id"], name: "index_derivatives_on_instrument_id"
    t.index ["security_id", "symbol_name", "exchange", "segment"], name: "index_derivatives_unique", unique: true
  end

  create_table "holdings", force: :cascade do |t|
    t.string "exchange"
    t.string "trading_symbol", null: false
    t.string "security_id", null: false
    t.string "isin", null: false
    t.integer "total_qty", null: false
    t.integer "dp_qty"
    t.integer "t1_qty"
    t.integer "available_qty", null: false
    t.integer "collateral_qty"
    t.decimal "avg_cost_price", precision: 15, scale: 2, null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "instruments", force: :cascade do |t|
    t.string "exchange", null: false
    t.string "segment", null: false
    t.string "security_id", null: false
    t.string "symbol_name"
    t.string "display_name"
    t.string "isin"
    t.string "instrument"
    t.string "instrument_type"
    t.string "underlying_symbol"
    t.string "underlying_security_id"
    t.string "series"
    t.integer "lot_size"
    t.decimal "tick_size", precision: 10, scale: 4
    t.string "asm_gsm_flag"
    t.string "asm_gsm_category"
    t.decimal "mtf_leverage", precision: 5, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument"], name: "index_instruments_on_instrument"
    t.index ["security_id", "symbol_name", "exchange", "segment"], name: "index_instruments_unique", unique: true
  end

  create_table "levels", force: :cascade do |t|
    t.bigint "instrument_id", null: false
    t.decimal "high"
    t.decimal "low"
    t.decimal "open"
    t.decimal "close"
    t.decimal "volume"
    t.decimal "demand_zone"
    t.decimal "supply_zone"
    t.string "timeframe"
    t.date "period_start"
    t.date "period_end"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument_id"], name: "index_levels_on_instrument_id"
  end

  create_table "margin_requirements", force: :cascade do |t|
    t.string "requirementable_type", null: false
    t.bigint "requirementable_id", null: false
    t.decimal "buy_co_min_margin_per"
    t.decimal "sell_co_min_margin_per"
    t.decimal "buy_bo_min_margin_per"
    t.decimal "sell_bo_min_margin_per"
    t.decimal "buy_co_sl_range_max_perc"
    t.decimal "sell_co_sl_range_max_perc"
    t.decimal "buy_co_sl_range_min_perc"
    t.decimal "sell_co_sl_range_min_perc"
    t.decimal "buy_bo_sl_range_max_perc"
    t.decimal "sell_bo_sl_range_max_perc"
    t.decimal "buy_bo_sl_range_min_perc"
    t.decimal "sell_bo_sl_min_range"
    t.decimal "buy_bo_profit_range_max_perc"
    t.decimal "sell_bo_profit_range_max_perc"
    t.decimal "buy_bo_profit_range_min_perc"
    t.decimal "sell_bo_profit_range_min_perc"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["requirementable_type", "requirementable_id"], name: "index_margin_requirements_on_requirementable", unique: true
  end

  create_table "mis_details", force: :cascade do |t|
    t.bigint "instrument_id", null: false
    t.string "isin"
    t.integer "mis_leverage"
    t.integer "bo_leverage"
    t.integer "co_leverage"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument_id"], name: "index_mis_details_on_instrument_id"
  end

  create_table "order_features", force: :cascade do |t|
    t.string "featureable_type", null: false
    t.bigint "featureable_id", null: false
    t.string "bracket_flag"
    t.string "cover_flag"
    t.string "buy_sell_indicator"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["featureable_type", "featureable_id"], name: "index_order_features_on_featureable"
  end

  create_table "orders", force: :cascade do |t|
    t.string "dhan_order_id", null: false
    t.string "correlation_id"
    t.string "transaction_type", null: false
    t.string "product_type", null: false
    t.string "order_type", null: false
    t.string "validity"
    t.string "exchange_segment"
    t.string "security_id", null: false
    t.integer "quantity", null: false
    t.integer "disclosed_quantity"
    t.decimal "price", precision: 15, scale: 2
    t.decimal "trigger_price", precision: 15, scale: 2
    t.decimal "bo_profit_value", precision: 15, scale: 2
    t.decimal "bo_stop_loss_value", precision: 15, scale: 2
    t.decimal "ltp", precision: 15, scale: 2
    t.string "order_status"
    t.integer "filled_qty"
    t.decimal "average_traded_price", precision: 15, scale: 2
    t.bigint "alert_id"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "oms_error_code"
    t.string "oms_error_description"
    t.index ["alert_id"], name: "index_orders_on_alert_id"
  end

  create_table "positions", force: :cascade do |t|
    t.bigint "instrument_id"
    t.string "trading_symbol", null: false
    t.string "security_id", null: false
    t.string "position_type", null: false
    t.string "exchange_segment"
    t.string "product_type", null: false
    t.decimal "buy_avg", precision: 15, scale: 2
    t.decimal "sell_avg", precision: 15, scale: 2
    t.integer "buy_qty"
    t.integer "sell_qty"
    t.integer "net_qty"
    t.decimal "cost_price", precision: 15, scale: 2
    t.decimal "realized_profit", precision: 15, scale: 2
    t.decimal "unrealized_profit", precision: 15, scale: 2
    t.decimal "rbi_reference_rate", precision: 15, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["instrument_id"], name: "index_positions_on_instrument_id"
  end

  create_table "postback_logs", force: :cascade do |t|
    t.bigint "order_id"
    t.string "dhan_order_id"
    t.string "event"
    t.jsonb "payload"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "strategies", force: :cascade do |t|
    t.string "name", null: false
    t.text "objective"
    t.text "how_it_works"
    t.text "risk"
    t.text "reward"
    t.text "best_used_when"
    t.text "example"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  add_foreign_key "alerts", "instruments"
  add_foreign_key "derivatives", "instruments"
  add_foreign_key "levels", "instruments"
  add_foreign_key "mis_details", "instruments"
  add_foreign_key "orders", "alerts"
  add_foreign_key "positions", "instruments"
end
