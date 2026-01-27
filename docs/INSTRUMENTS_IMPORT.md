# Instruments import: CSV and schema mapping

The Dhan API scrip master CSV is imported by `InstrumentsImporter`. Entry points:

- **`bin/rails import:instruments`** — calls `import_from_url` (fetch with 24h cache, import, persist stats to AppSetting).
- **`InstrumentsImporter.import(file_path)`** — when `file_path` is `nil`, behaves like `import_from_url`; when provided, reads that file and runs `import_from_csv` without recording stats.
- **`InstrumentsImporter.import_from_csv(csv_content)`** — parses CSV, runs `build_batches` → `import_instruments!` → `import_derivatives!`, returns a summary hash.

**Reference implementation:** `algo_scalper_api` — `app/services/instruments_importer.rb` (import_from_url, import_from_csv, fetch_csv_with_cache, build_batches, attach_instrument_ids via InstrumentTypeMapping.underlying_for). This app keeps column name **`instrument`** (not `instrument_code`), supports NSE/BSE/MCX, and uses a smaller schema (no margin/BO/CO fields). CSV is cached at `tmp/dhan_scrip_master.csv` for 24 hours.

## Data model

- **Instruments**: Underlyings (EQUITY, INDEX, currency/commodity underlyings). Rows with `SEGMENT != 'D'` and `EXCH_ID` in `VALID_EXCHANGES` (NSE, BSE, MCX). Unique on `(security_id, symbol_name, exchange, segment)`.
- **Derivatives**: Options/futures with `SEGMENT == 'D'`. Linked via `instrument_id`; resolved by `[InstrumentTypeMapping.underlying_for(INSTRUMENT), UNDERLYING_SYMBOL]` (e.g. `['INDEX','NIFTY']`).

## CSV source

- URL: `https://images.dhan.co/api-data/api-scrip-master-detailed.csv`
- Cache: `tmp/dhan_scrip_master.csv`, 24h; fallback to cache if download fails.

## CSV → instruments table

| CSV column         | DB column (instruments) |
|--------------------|--------------------------|
| EXCH_ID            | exchange                 |
| SEGMENT            | segment                  |
| SECURITY_ID        | security_id              |
| SYMBOL_NAME        | symbol_name              |
| DISPLAY_NAME       | display_name             |
| ISIN               | isin                     |
| INSTRUMENT         | instrument               |
| INSTRUMENT_TYPE    | instrument_type          |
| UNDERLYING_SYMBOL  | underlying_symbol        |
| UNDERLYING_SECURITY_ID | underlying_security_id |
| SERIES             | series                   |
| LOT_SIZE           | lot_size                 |
| TICK_SIZE          | tick_size                |
| ASM_GSM_FLAG       | asm_gsm_flag             |
| ASM_GSM_CATEGORY   | asm_gsm_category         |
| MTF_LEVERAGE       | mtf_leverage             |

Row hashes are built from `build_attrs(row)` and then **sliced by `Instrument.column_names`** (excluding `id`), so new columns added via migrations are picked up automatically once mapped in `build_attrs`.

## CSV → derivatives table

| CSV column         | DB column (derivatives) |
|--------------------|--------------------------|
| EXCH_ID            | exchange                 |
| SEGMENT            | segment                  |
| SECURITY_ID        | security_id              |
| SYMBOL_NAME        | symbol_name              |
| DISPLAY_NAME       | display_name             |
| ISIN               | isin                     |
| INSTRUMENT         | instrument               |
| INSTRUMENT_TYPE    | instrument_type          |
| UNDERLYING_SYMBOL  | underlying_symbol        |
| UNDERLYING_SECURITY_ID | underlying_security_id |
| SERIES             | series                   |
| SM_EXPIRY_DATE     | expiry_date              |
| STRIKE_PRICE       | strike_price             |
| OPTION_TYPE        | option_type              |
| EXPIRY_FLAG        | expiry_flag              |
| LOT_SIZE           | lot_size                 |
| TICK_SIZE          | tick_size                |
| ASM_GSM_FLAG       | asm_gsm_flag             |
| (resolved)         | instrument_id            |

Derivative rows are built from `build_attrs` and sliced by **`Derivative.column_names`**; `instrument_id` is set in `attach_instrument_ids`.

## Resolving instrument_id for derivatives

Lookup key is `[InstrumentTypeMapping.underlying_for(INSTRUMENT), UNDERLYING_SYMBOL.upcase]` (e.g. `['INDEX','NIFTY']`). The importer plucks `(id, instrument, underlying_symbol)` from instruments and builds this map, so derivatives resolve even when instruments were imported in a previous run.

## Keeping schema and importer in sync

1. **New columns**: Add a migration, run it, then add the CSV→attribute in `build_attrs` and (if needed) to the `on_duplicate_key_update` `columns` list for instruments or derivatives.
2. **Renaming columns**: Add a migration and update the importer mapping and conflict/update lists.
3. **DB out of sync**: Align DB to the repo with `bin/rails db:migrate` (or reset if required), then run `bin/rails import:instruments`.
