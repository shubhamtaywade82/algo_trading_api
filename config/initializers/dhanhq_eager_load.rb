# frozen_string_literal: true

# Keeps the DhanHQ gem out of Rails' eager loading.
#
# Production sets `eager_load = true`, and Rails then calls
# `Zeitwerk::Loader.eager_load_all`, which force-loads *every* registered
# Zeitwerk loader — including the ones inside gems. The DhanHQ gem has file
# names its own inflector does not resolve, so that pass raises and the boot
# dies before the app serves a request:
#
#   3.2.1: expected .../DhanHQ/mcp.rb to define constant DhanHQ::Mcp
#   3.3.0: expected .../DhanHQ/contracts/edis_contract.rb to define
#          constant DhanHQ::Contracts::EdisContract   (that file defines
#          EdisFormContract and EdisBulkFormContract, and no such constant
#          exists at all)
#
# Nothing catches this in development, where `eager_load` is false and the
# files are simply never loaded — so it only ever appears as a failed deploy.
#
# Excluding the gem's own root restores exactly the development behaviour: its
# constants stay autoloadable and resolve on first reference, they are just not
# force-loaded at boot. That is version-proof, where chasing each bad filename
# is not.
#
# Only this app's own code needs eager loading, and it still gets it.
loader = nil
# Zeitwerk::Registry::Loaders responds to `each` but is not Enumerable, so
# `find` would raise NoMethodError here.
Zeitwerk::Registry.loaders.each { |candidate| loader = candidate if candidate.tag == 'dhanhq' }

if loader.respond_to?(:do_not_eager_load) && loader.dirs.any?
  loader.do_not_eager_load(*loader.dirs)
else
  Rails.logger&.warn('[dhanhq] could not exclude the gem from eager loading; production boot may fail')
end
