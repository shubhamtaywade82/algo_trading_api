# lib/tasks/import_mis_data.rake
namespace :data do
  desc "Import MIS Details from CSV"
  task import_mis: :environment do
    require "csv"

    # Reference the CSV file in the root folder
    file_path = Rails.root.join("mis_data.csv")

    # Check if the file exists
    unless File.exist?(file_path)
      puts "File not found at #{file_path}. Please make sure the file is present in the root folder."
      exit
    end

    CSV.foreach(file_path, headers: true) do |row|
      instruments = Instrument.where(underlying_symbol: row["Symbol / Scrip Name"]).where("segment = 'E'")

      next unless instruments.any?

      instruments.each do |instrument|
        if instrument
          m = MisDetail.create!(
            instrument: instrument,
            isin: row["ISIN"],
            mis_leverage: row["MIS(Intraday)"].delete("x").to_f,
            bo_leverage: row["BO(Bracket)"] ? row["BO(Bracket)"].delete("x").to_f : nil,
            co_leverage: row["CO(Cover)"] ? row["CO(Cover)"].delete("x").to_f : nil
          )

          pp m
        else
          Rails.logger.warn "Instrument not found for Symbol: #{row['Symbol / Scrip Name']}"
        end
      end
    end

    puts "MIS data imported successfully!"
  end
end
