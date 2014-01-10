require 'fileutils'
require File.expand_path(File.join(File.dirname(__FILE__), '..', '..', '..', '..', 'helpers', 'file_searching'))

class MongoServer
  include NewRelic::TestHelpers::FileSearching

  attr_reader :type
  attr_accessor :port

  def initialize(type = :single)
    @type = type
    @port = next_available_port

    make_directories
  end

  def make_directories
    directories = [
      port_lock_directory,
      pid_directory,
      db_directory,
      log_directory,
      db_path
    ]

    FileUtils.mkdir_p(directories)
  end

  def tmp_directory
    File.join(gem_root, 'tmp')
  end

  def port_lock_directory
    File.join(tmp_directory, 'ports')
  end

  def port_lock_path
    File.join(port_lock_directory, "#{self.port}.lock")
  end

  def pid_directory
    File.join(tmp_directory, 'pids')
  end

  def pid_path
    File.join(pid_directory, "#{self.port}.pid")
  end

  def db_directory
    File.join(tmp_directory, 'db')
  end

  def db_path
    File.join(db_directory, "data_#{self.port}")
  end

  def log_directory
    File.join(tmp_directory, 'log')
  end

  def log_path
    File.join(log_directory, "#{self.port}.log")
  end

  def start
    lock_port
    `#{startup_command}`
    self
  end

  def startup_command
    pid_file = "--pidfilepath #{pid_path}"
    log_file = "--logpath #{log_path} "

    dbpath = "--dbpath #{db_path}"
    port_flag = "--port #{self.port}"
    small_mongo = "--oplogSize 128 --smallfiles"
    repl_set = "--fork --replSet multiverse"

    base = "#{port_flag} #{pid_file} #{log_file} #{small_mongo} #{dbpath}"

    if self.type == :single
      "mongod #{base} &"
    elsif self.type == :replica
      "mongod #{repl_set} #{base} &"
    end
  end

  def stop
    return self unless pid
    Process.kill('TERM', pid)
    release_port
    self
  rescue Errno::ESRCH => e
    raise e unless e.message == 'No such process'
  end

  def running?
    return false unless pid
    Process.kill(0, pid) == 1
  rescue Errno::ESRCH => e
    raise e unless e.message == 'No such process'
    false
  end

  def pid
    File.read(pid_path).to_i if File.exists? pid_path
  end

  def next_available_port
    used_ports = all_port_lock_files.map do |filename|
      File.read(filename).to_i
    end

    if used_ports.empty?
      27017
    else
      used_ports.sort.last + 1
    end
  end

  def all_port_lock_files
    Dir.glob(File.join(port_lock_directory, '*.lock'))
  end

  def lock_port
    File.write(port_lock_path, self.port)
  end

  def release_port
    FileUtils.rm port_lock_path, force: true
  end
end
