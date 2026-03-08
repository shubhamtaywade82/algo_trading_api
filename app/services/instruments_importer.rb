# frozen_string_literal: true

# Orchestrates the importing of Dhan API scrip master CSV into instruments and derivatives.
class InstrumentsImporter < ApplicationService
  def self.import_from_url
    new.import_from_url
  end

  def self.import(file_path = nil)
    new.import(file_path)
  end

  def import_from_url
    started_at = Time.current
    csv_content = InstrumentsImport::Fetcher.call
    summary = process_csv(csv_content)

    summary[:started_at] = started_at
    summary[:finished_at] = Time.current
    summary[:duration] = summary[:finished_at] - started_at

    record_success!(summary)
    summary
  end

  def import(file_path = nil)
    started_at = Time.current
    csv_content = InstrumentsImport::Fetcher.call(file_path: file_path)
    summary = process_csv(csv_content)

    if file_path.nil?
      summary[:finished_at] = Time.current
      summary[:duration] = summary[:finished_at] - started_at
      record_success!(summary)
    end

    summary
  end

  def self.import_from_csv(csv_content)
    new.import_from_csv(csv_content)
  end

  def import_from_csv(csv_content)
    process_csv(csv_content)
  end

  private

  def process_csv(csv_content)
    parsed_data = InstrumentsImport::Parser.call(csv_content)

    # First, import instruments to get IDs for mapping
    # Note: Using Upserter here just for Instruments so we have them available in Mapper
    InstrumentsImport::Upserter.call(
      instruments_rows: parsed_data[:instruments],
      derivatives_rows: []
    )

    mapped_derivatives = InstrumentsImport::Mapper.call(parsed_data[:derivatives])

    # Then, import derivatives with the mapped IDs
    upsert_results = InstrumentsImport::Upserter.call(
      instruments_rows: [],
      derivatives_rows: mapped_derivatives[:with_parent]
    )

    {
      instrument_rows: parsed_data[:instruments].size,
      derivative_rows: parsed_data[:derivatives].size,
      instrument_upserts: parsed_data[:instruments].size, # Assuming all were upserted
      derivative_upserts: upsert_results[:derivative_upserts],
      instrument_total: Instrument.count,
      derivative_total: Derivative.count
    }
  end

  def record_success!(summary)
    return unless defined?(AppSetting) && AppSetting.respond_to?(:[]=)

    write_setting('instruments.last_imported_at', summary[:finished_at]&.iso8601)
    write_setting('instruments.last_import_duration_sec', summary[:duration]&.then { |d| d.to_f.round(2).to_s })
    write_setting('instruments.last_instrument_rows', summary[:instrument_rows].to_s)
    write_setting('instruments.last_derivative_rows', summary[:derivative_rows].to_s)
    write_setting('instruments.last_instrument_upserts', summary[:instrument_upserts].to_s)
    write_setting('instruments.last_derivative_upserts', summary[:derivative_upserts].to_s)
    write_setting('instruments.instrument_total', summary[:instrument_total].to_s)
    write_setting('instruments.derivative_total', summary[:derivative_total].to_s)
  end

  def write_setting(key, value)
    return if value.blank?

    AppSetting[key] = value
  end
end
