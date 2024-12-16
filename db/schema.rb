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

ActiveRecord::Schema[8.0].define(version: 2024_12_16_022320) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "alerts", force: :cascade do |t|
    t.string "ticker", null: false
    t.string "instrument_type", null: false
    t.string "order_type", null: false
    t.string "current_position"
    t.string "previous_position"
    t.decimal "current_price", precision: 15, scale: 2, null: false
    t.decimal "high", precision: 15, scale: 2
    t.decimal "low", precision: 15, scale: 2
    t.decimal "volume", precision: 15, scale: 6
    t.datetime "time", null: false
    t.string "chart_interval"
    t.decimal "stop_loss", precision: 15, scale: 2
    t.decimal "take_profit", precision: 15, scale: 2
    t.decimal "trailing_stop_loss", precision: 15, scale: 2
    t.string "strategy_name", null: false
    t.string "strategy_id", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.string "status", default: "pending", null: false
    t.text "error_message"
    t.string "action"
    t.index ["instrument_type"], name: "index_alerts_on_instrument_type"
    t.index ["strategy_id"], name: "index_alerts_on_strategy_id"
    t.index ["ticker"], name: "index_alerts_on_ticker"
  end

  create_table "instruments", force: :cascade do |t|
    t.string "exch_id"
    t.string "segment"
    t.string "security_id"
    t.string "isin"
    t.string "instrument"
    t.string "underlying_symbol"
    t.string "symbol_name"
    t.string "display_name"
    t.string "instrument_type"
    t.integer "lot_size"
    t.date "sm_expiry_date"
    t.decimal "strike_price", precision: 10, scale: 2
    t.string "option_type"
    t.decimal "tick_size", precision: 10, scale: 2
    t.string "expiry_flag"
    t.string "asm_gsm_flag"
    t.decimal "buy_co_min_margin_per", precision: 10, scale: 2
    t.decimal "sell_co_min_margin_per", precision: 10, scale: 2
    t.decimal "buy_bo_min_margin_per", precision: 10, scale: 2
    t.decimal "sell_bo_min_margin_per", precision: 10, scale: 2
    t.decimal "mtf_leverage", precision: 10, scale: 2
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.index ["security_id"], name: "index_instruments_on_security_id", unique: true
  end

  create_table "orders", force: :cascade do |t|
    t.string "ticker"
    t.string "action"
    t.integer "quantity"
    t.decimal "price"
    t.string "status"
    t.string "security_id"
    t.string "dhan_order_id"
    t.string "dhan_status"
    t.decimal "stop_loss_price"
    t.decimal "take_profit_price"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end

  create_table "positions", force: :cascade do |t|
    t.string "ticker"
    t.string "action"
    t.integer "quantity"
    t.decimal "entry_price"
    t.decimal "stop_loss_price"
    t.decimal "take_profit_price"
    t.string "security_id"
    t.string "status"
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
  end
end
