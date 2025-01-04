namespace :data do
  desc "Import MIS Details from CSV"
  task import_mis: :environment do
    require "csv"

    # Define the path to the CSV file
    file_path = Rails.root.join("mis_data.csv")

    # Check if the file exists
    unless File.exist?(file_path)
      puts "File not found at #{file_path}. Please make sure the file is present in the root folder."
      exit
    end

    begin
      # Start processing the CSV file
      puts "Starting MIS data import from #{file_path}..."

      CSV.foreach(file_path, headers: true) do |row|
        # Skip rows with missing critical data
        if row["Symbol / Scrip Name"].blank?

          puts "Skipping row due to missing critical data: #{row.to_h}"
          Rails.logger.warn "Skipping row due to missing critical data: #{row.to_h}"
          next
        end

        # Fetch the associated instruments
        instruments = Instrument.where(underlying_symbol: row["Symbol / Scrip Name"], isin: row["ISIN"])

        if instruments.empty?
          Rails.logger.warn "No matching instruments found for Symbol: #{row['Symbol / Scrip Name']}, Exchange: #{row['Exchange ID']}, Segment: #{row['Segment Code']}"
          next
        end

        instruments.each do |instrument|
          # Update or create MIS details for the instrument
          mis_detail = MisDetail.find_or_initialize_by(instrument: instrument)
          mis_detail.assign_attributes(
            isin: row["ISIN"],
            mis_leverage: row["MIS(Intraday)"]&.delete("x")&.to_i,
            bo_leverage: row["BO(Bracket)"]&.delete("x")&.to_i,
            co_leverage: row["CO(Cover)"]&.delete("x")&.to_i
          )

          if mis_detail.save
            puts "Updated MIS details for Instrument: #{instrument.symbol_name} (#{instrument.security_id})"
          else
            Rails.logger.error "Failed to save MIS details for Instrument: #{instrument.symbol_name}. Errors: #{mis_detail.errors.full_messages.join(', ')}"
          end
        end
      end

      puts "MIS data import completed successfully!"
    rescue StandardError => e
      Rails.logger.error "An error occurred during MIS data import: #{e.message}"
      Rails.logger.error e.backtrace.join("\n")
      puts "MIS data import failed. Check the logs for details."
    end
  end
end
