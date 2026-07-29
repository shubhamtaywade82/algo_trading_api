# frozen_string_literal: true

require 'rails_helper'

# Guards the unbuffered-stdout lines in config/environments/production.rb and
# lib/tasks/live_feed.rake.
#
# Ruby leaves $stdout block-buffered whenever it is not a TTY, which on Render
# is always — logs are captured through a pipe. The buffer flushes at 8 KB or
# on exit, and `live:paper_engine` is a daemon that does neither for a whole
# trading session. At a ~75-byte heartbeat every 180s it needs ~5.5 hours to
# fill 8 KB, longer than the 6h15m session, so a perfectly healthy engine
# showed an empty log all day and looked like it had never started.
#
# Puma sets sync itself, so the web service was never affected and this stayed
# invisible until the first rake worker was deployed. `bin/ws_feed` has carried
# the line since it was written; the daemon rake tasks did not.
#
# These examples exercise the real mechanism in a subprocess rather than
# asserting on `$stdout.sync` in-process, where RSpec's own reporter has
# already touched the IO.
RSpec.describe 'daemon stdout buffering' do
  # A long-running process in the shape of `live:paper_engine`: it writes a
  # heartbeat well under 8 KB, then stays alive. Returns whatever a reader can
  # see while it is still running.
  def output_visible_while_alive(sync:)
    script = <<~RUBY
      $stdout.sync = true if #{sync}
      require 'logger'
      Logger.new($stdout).info('[DHAN] paper engine heartbeat')
      puts '[engine] connected=true ticks=3 subs=3 open=0 net_pnl=0.0'
      sleep 30
    RUBY

    read_io, write_io = IO.pipe
    pid = Process.spawn(RbConfig.ruby, '-e', script, out: write_io, err: File::NULL)
    write_io.close

    # Give the child time to write and, if it is going to, flush.
    seen = +''
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + 3
    while Process.clock_gettime(Process::CLOCK_MONOTONIC) < deadline
      begin
        seen << read_io.read_nonblock(4096)
        break
      rescue IO::WaitReadable
        IO.select([read_io], nil, nil, 0.1)
      rescue EOFError
        break
      end
    end
    seen
  ensure
    if pid
      Process.kill('KILL', pid)
      Process.wait(pid)
    end
    read_io&.close
  end

  it 'reaches the log collector while the daemon is still running' do
    expect(output_visible_while_alive(sync: true)).to include('paper engine heartbeat', '[engine] connected=true')
  end

  # The failure mode itself. If this ever stops holding, Ruby changed its
  # default and the sync lines are merely redundant rather than load-bearing.
  it 'is swallowed entirely without the sync line' do
    expect(output_visible_while_alive(sync: false)).to be_empty
  end

  describe 'the entry points that need it' do
    # Read as UTF-8 explicitly: both files carry box-drawing and emoji, and a
    # host whose default external encoding is not UTF-8 would otherwise fail
    # these on an encoding error rather than on the thing being asserted.
    def source(path)
      File.read(Rails.root.join(path), encoding: 'UTF-8')
    end

    it 'is set in the production environment, covering the deployed worker' do
      expect(source('config/environments/production.rb')).to include('$stdout.sync = true')
    end

    # Repeated in the tasks because the trap is a property of the process
    # shape, not the environment: the same daemon run in development under a
    # supervisor buffers identically.
    it 'is set by both long-running rake daemons' do
      rakefile = source('lib/tasks/live_feed.rake')

      expect(rakefile).to include('def unbuffer_stdout!', '$stdout.sync = true')
      expect(rakefile).to match(/task feed: :environment do\s*\n\s*unbuffer_stdout!/)
      expect(rakefile).to match(/task paper_engine: :environment do\s*\n\s*unbuffer_stdout!/)
    end
  end
end
