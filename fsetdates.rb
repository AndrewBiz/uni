#!/usr/bin/env ruby -w
# encoding: UTF-8
require_relative "anb_lib.rb"

# ********** MAIN PROGRAM **********
begin #*** GLOBAL BLOCK
  $log = ANBLogger.new(File.basename(($PROGRAM_NAME), File.extname($PROGRAM_NAME))+".log")
  $log.level = ANBLogger::DEBUG #DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
  $log << "\n"
  $log.info "****** STARTING command #{$PROGRAM_NAME} #{ARGV.inspect}"

  dir_to_process, yaml_name = read_input_params
   
  param = Parameters.new(yaml_name, dir_to_process)

  ANB_exiftool.init_collection param.dir_original, param.file_ext

  ANB_exiftool.backup_files param.dir_backup

  ANB_exiftool.move_files param.dir_target

  date2set = DateTime.strptime(param.options[:metadata][:date2set], $DateTimeFormat)  
  delta = param.options[:metadata][:delta].to_i
  ANB_exiftool.batch_set_dates_smart(param.dir_target, date2set, delta)      
  
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
