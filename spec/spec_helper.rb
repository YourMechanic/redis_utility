# frozen_string_literal: true

require 'redis_utility'
require 'redis'

RSpec.configure do |config|
  # Enable flags like --only-failures and --next-failure
  config.example_status_persistence_file_path = '.rspec_status'

  # Disable RSpec exposing methods globally on `Module` and `main`
  config.disable_monkey_patching!

  config.expect_with :rspec do |c|
    c.syntax = :expect
  end
end

# Start our own redis-server to avoid corrupting any others
REDIS_BIN  = 'redis-server'
REDIS_PORT = ENV['REDIS_PORT'] || 9212
REDIS_HOST = ENV['REDIS_HOST'] || 'localhost'
REDIS_PID  = 'redis.pid'  # can't be absolute
REDIS_DUMP = 'redis.rdb'  # can't be absolute
REDIS_RUNDIR = File.dirname(__FILE__)

def start_redis
  puts "=> Starting redis-server on #{REDIS_HOST}:#{REDIS_PORT}"
  fork do
    system "cd #{REDIS_RUNDIR} && (echo port #{REDIS_PORT}; " \
           'echo logfile /dev/null; echo daemonize yes; ' \
           "echo pidfile #{REDIS_PID}; echo dbfilename #{REDIS_DUMP}; " \
           "echo databases 32) | #{REDIS_BIN} -"
  end
  sleep 2
end

def kill_redis
  pidfile = File.expand_path REDIS_PID,  REDIS_RUNDIR
  rdbfile = File.expand_path REDIS_DUMP, REDIS_RUNDIR
  pid = File.read(pidfile).to_i
  puts "=> Killing #{REDIS_BIN} with pid #{pid}"
  Process.kill 'TERM', pid
  Process.kill 'KILL', pid
  File.unlink pidfile
  File.unlink rdbfile if File.exist? rdbfile
end

# Start redis-server except under JRuby
unless defined?(RUBY_ENGINE) && RUBY_ENGINE == 'jruby'
  start_redis

  at_exit do
    kill_redis
  end
end

RedisUtility.redis_config = {
  host: REDIS_HOST
}.freeze
