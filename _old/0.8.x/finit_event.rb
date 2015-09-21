#!/usr/bin/env ruby -U
# encoding: UTF-8
require_relative "foto_lib.rb"
require "docopt"

# ********** MAIN PROGRAM **********
usage = <<DOCOPT
Init foto event program, version #{VERSION}
Usage:
  #{File.basename(__FILE__)} [-e EVT] [-a NICKNAME]
  #{File.basename(__FILE__)} -h | --help
  #{File.basename(__FILE__)} --version

Options:
  -h --help     Show this screen.
  --version     Show version.
  -e EVT --event=EVT  Event profile to use [default: ./event.yml]
  -a NICKNAME --author=NICKNAME  Author nickname
DOCOPT

begin #*** GLOBAL BLOCK
  $log = ANBLogger.new(File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME))+".log")
  $log.level = ANBLogger::INFO #DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
  $log << "\n"
  $log.info "****** STARTING command #{$PROGRAM_NAME} #{ARGV.inspect}"
  $log.info "VERSION #{VERSION}"

  # init program parameters
  options_cli = Docopt::docopt(usage, version: VERSION) 

  # program configuration
  dir_config = ["."]
  dir_config << File.join(ENV['HOME'], File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME)))
  dir_config << File.dirname($PROGRAM_NAME)
  yaml_config = ANBConfig.get_1st_yaml(dir_config, "*#{File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME))}_conf*")
  options_cfg = ANBConfig.load_yaml yaml_config

  # dir to process
  dir_to_process = Dir.pwd
  fail("#{dir_to_process} does not exist") unless File.exist?(dir_to_process) 
  fail("#{dir_to_process} is not a Directory") unless File.directory?(dir_to_process)

  # event profile 
  foto_event = FotoEvent.new(options_cfg, options_cli, dir_to_process)

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
  
  # process txt files
  if options_cfg[:input_parameter][:txt_files_process]
    FotoObject.batch_process_txt_files options_cfg[:input_parameter][:txt_files_process_list], dir_to_process, foto_event.dir_target, foto_event.dir_backup
  end  
      

rescue Docopt::Exit => e
  puts e.message

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
