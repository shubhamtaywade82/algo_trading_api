# frozen_string_literal: true

# The CHECK constraints in 20260727140000 are added NOT VALID so a deploy is
# never blocked by rows that predate them. They already guard every new write;
# this promotes them to fully validated once the table is clean, and tells you
# exactly what is dirty when it is not.
namespace :instruments do
  desc 'Report rows violating the instrument/derivative CHECK constraints and validate the clean ones'
  task validate_constraints: :environment do
    connection = ActiveRecord::Base.connection
    pending = connection.select_rows(<<~SQL.squish)
      SELECT rel.relname, con.conname, pg_get_constraintdef(con.oid)
      FROM pg_constraint con
      JOIN pg_class rel ON rel.oid = con.conrelid
      WHERE con.contype = 'c'
        AND NOT con.convalidated
        AND rel.relname IN ('instruments', 'derivatives')
      ORDER BY rel.relname, con.conname
    SQL

    if pending.empty?
      puts 'All instrument/derivative CHECK constraints are already validated.'
      next
    end

    failures = 0

    pending.each do |table, name, definition|
      # "CHECK ((expr)) NOT VALID" -> "expr"
      expression = definition[/\ACHECK \((.*?)\)(?: NOT VALID)?\z/m, 1]
      offenders = connection.select_value("SELECT COUNT(*) FROM #{table} WHERE NOT (#{expression})").to_i

      if offenders.positive?
        failures += 1
        puts "✗ #{name}: #{offenders} row(s) violate #{expression}"
        puts "  inspect with: #{table}.where.not(#{expression.inspect})"
        next
      end

      connection.execute("ALTER TABLE #{table} VALIDATE CONSTRAINT #{connection.quote_column_name(name)}")
      puts "✓ #{name}: validated"
    end

    abort("\n#{failures} constraint(s) still have violating rows. Fix the data, then re-run.") if failures.positive?
  end
end
