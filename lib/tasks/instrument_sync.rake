namespace :instruments do
  desc "Sync instruments from Dhan API"
  task sync: :environment do
    InstrumentSyncService.sync_instruments
  end
end
