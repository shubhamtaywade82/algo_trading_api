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
      debugger
      # Fetch the associated instrument
      instruments = Instrument.joins(:exchange, :segment)
                               .where(underlying_symbol: row["Symbol / Scrip Name"])
                               .where(exchange: { exch_id: row["Exchange ID"] })
                               .where(segment: { segment_code: row["Segment Code"] })

      if instruments.empty?
        Rails.logger.warn "No matching instruments found for Symbol: #{row['Symbol / Scrip Name']}, Exchange: #{row['Exchange ID']}, Segment: #{row['Segment Code']}"
        next
      end

      instruments.each do |instrument|
        # Update or create MIS details for the instrument
        mis_detail = MisDetail.find_or_initialize_by(instrument: instrument)
        mis_detail.assign_attributes(
          isin: row["ISIN"],
          mis_leverage: row["MIS(Intraday)"]&.delete("x")&.to_f,
          bo_leverage: row["BO(Bracket)"]&.delete("x")&.to_f,
          co_leverage: row["CO(Cover)"]&.delete("x")&.to_f
        )



        if mis_detail.save
          puts "Updated MIS details for Instrument: #{instrument.symbol_name} (#{instrument.security_id})"
        else
          Rails.logger.error "Failed to save MIS details for Instrument: #{instrument.symbol_name}. Errors: #{mis_detail.errors.full_messages.join(', ')}"
        end
      end
    end

    puts "MIS data imported successfully!"
  end
end
