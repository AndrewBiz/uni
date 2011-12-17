#!/usr/bin/env ruby -w
# encoding: UTF-8
require_relative "anb_lib.rb"

# ********** MAIN PROGRAM **********
begin #*** GLOBAL BLOCK
  $log = ANBLogger.new(File.basename(($PROGRAM_NAME), File.extname($PROGRAM_NAME))+".log")
  $log.level = ANBLogger::DEBUG #DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
  $log << "\n"
  $log.info "****** STARTING command #{$PROGRAM_NAME} #{ARGV.inspect}"

  dir_to_process = Dir.pwd
  dir_backup = File.join(dir_to_process, "backup")
  force = true

  location2set = ARGV[0]||""
  fail("No location to set;") if location2set.empty?

  yaml_name = File.join(File.dirname($PROGRAM_NAME), "locations.yaml")
  fail("#{yaml_name} - no YAML File found;") unless File.file?(yaml_name)
  locations = YAML.load_file(yaml_name)
  $log.info "YAML loaded: #{yaml_name}"

  loc = locations[location2set.downcase]||{}
  fail("Location #{location2set} not found in #{yaml_name}") if loc.empty?

  gps_created = loc[:gps_created]||{}
  fail("No gps info for #{location2set}") if gps_created.empty?
   
  ANB_exiftool.init_collection dir_to_process, ["jpg"]
  ANB_exiftool.backup_files dir_backup 

  ANB_exiftool.batch_set_gps(dir_to_process, gps_created, force)
  
rescue Parameters::FatalError => e
  $log.fatal e.full_backtrace_message 
  $stderr.puts "Exit on FATAL (Parameters) errors. See #{$log.logdev.filename} for details"
  exit false

rescue StandardError => e
  $log.fatal e.full_backtrace_message 
  $stderr.puts "Exit on FATAL (StandardError) errors. See #{$log.logdev.filename} for details"
  exit false
  
rescue SignalException => e
  $log.fatal e.full_message("User hit Ctrl-C;") 
  $stderr.puts "Exit on user interrupt Ctrl-C"
  exit false

rescue Exception => e
  $log.fatal e.full_backtrace_message 
  $stderr.puts "Exit on FATAL errors. See #{$log.logdev.filename} for details"
  exit false

else
  # No Exceptions = All is Ok

ensure
  # Do it anyway
  $log.info "****** ENDING command #{$PROGRAM_NAME}"
  $log << "\n"
  $log.close
end # *** GLOBAL BLOCK
