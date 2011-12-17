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
   
  ANB_exiftool.init_collection dir_to_process, ["jpg"]

  ANB_exiftool.batch_fix_fmd dir_to_process
  
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
