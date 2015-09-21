#!/usr/bin/env ruby -w
# encoding: UTF-8
require_relative "foto_lib.rb"

# ********** MAIN PROGRAM **********
begin #*** GLOBAL BLOCK
  $log = ANBLogger.new(File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME))+".log")
  $log.level = ANBLogger::INFO #DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
  $log << "\n"
  $log.info "****** STARTING command #{$PROGRAM_NAME} #{ARGV.inspect}, version #{VERSION}"

  # init program parameters

  # program configuration
  dir_config = ["."]
  dir_config << File.join(ENV['HOME'], File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME)))
  dir_config << File.dirname($PROGRAM_NAME)
  yaml_config = ARGV[0]||ANBConfig.get_1st_yaml(dir_config, "*#{File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME))}_conf*")

  # dir to process
  dir_to_process = Dir.pwd
  fail("#{dir_to_process} does not exist") unless File.exist?(dir_to_process) 
  fail("#{dir_to_process} is not a Directory") unless File.directory?(dir_to_process)

  # event profile
  yaml_event = ANBConfig.get_1st_yaml(["."], "event*")
   
  foto_event = FotoEvent.new(yaml_config, yaml_event, dir_to_process)

  FotoObject.init_collection foto_event

  FotoObject.backup_files foto_event.dir_backup
  FotoObject.move_files foto_event.dir_tmp
  
  FotoObject.batch_set_tags(foto_event.dir_tmp, :creator => foto_event.creator, 
    :copyright => foto_event.copyright, :keywords => foto_event.keywords, 
    :location_created => foto_event.location_created, :gps_created => foto_event.gps_created, 
    :collection_name => foto_event.collection_name, :collection_uri => foto_event.collection_uri,
    :force => false)
  
  FotoObject.batch_fix_fmd foto_event.dir_tmp

  FotoObject.move_files foto_event.dir_target
      

rescue ANBConfig::FatalError => e
  $log.fatal e.full_message 
  $stderr.puts "Exit on FATAL (ANBConfig) errors. See #{$log.logdev.filename} for details"
  exit false

rescue FotoEvent::FatalError => e
  $log.fatal e.full_message 
  $stderr.puts "Exit on FATAL (FotoEvent) errors. See #{$log.logdev.filename} for details"
  exit false

rescue StandardError => e
  $log.fatal e.full_message 
  $stderr.puts "Exit on FATAL (StandardError) errors. See #{$log.logdev.filename} for details"
  exit false
  
rescue SignalException => e
  $log.fatal e.full_message("User hit Ctrl-C;") 
  $stderr.puts "Exit on user interrupt Ctrl-C"
  exit false

rescue Exception => e
  $log.fatal e.full_message 
  $stderr.puts "Exit on FATAL errors. See #{$log.logdev.filename} for details"
  exit false

else
  # No Exceptions = All is Ok

ensure
  # Do it anyway
  $log.info "****** TERMINATING command #{$PROGRAM_NAME}"
  $log << "\n"
  $log.close
end # *** GLOBAL BLOCK
