#!/usr/bin/env ruby -w
# encoding: UTF-8
require_relative "anb_lib.rb"

# Video Class
class Video < ANB_exiftool

  # Testing video file
  def check event
    # read exif info
    begin 
      exif = MiniExiftool.new filename, :timestamps => DateTime #, :convert_encoding => true
      @date_time_original = exif.date_time_original||exif.create_date||false
      @file_modify_date = exif.file_modify_date||false
      @metadata = exif.to_hash

      raise Error, "- date_time_original = 00.00.00;" unless @date_time_original 
      raise Error, "- date_time_original NOT in event dates;" unless (@date_time_original >= event.date_start) and (@date_time_original <= event.date_end)
       
      # generate names
      generate_target_name event.author_nikname

    rescue MiniExiftool::Error => e
      add_error e.full_backtrace_message(@name+@extention)      
    rescue Error => e
      add_error e.full_message(@name+@extention)      
    rescue StandardError => e
      add_error e.full_backtrace_message(@name+@extention)
    end
  end #check

end #class
 

# ********** MAIN PROGRAM **********
begin #*** GLOBAL BLOCK
  $log = ANBLogger.new(File.basename(($PROGRAM_NAME), File.extname($PROGRAM_NAME))+".log")
  $log.level = ANBLogger::DEBUG #DEBUG < INFO < WARN < ERROR < FATAL < UNKNOWN
  $log << "\n"
  $log.info "****** STARTING command #{$PROGRAM_NAME} #{ARGV.inspect}"
  
  # input parameters
  dir_to_process, yaml_name = read_input_params

  ext_to_process = ["mts", "mov", "mp4", "avi", "wmv"]
  dir_to_process = Dir.pwd
  dir_backup = File.join(dir_to_process, "backup")
  dir_target_parent = "."
  
  event = ANB_event.new yaml_name, dir_to_process

  Video.init_collection dir_to_process, ext_to_process
  
  tags_to_read = [:date_time_original, :create_date]
  Video.batch_read_metadata dir_to_process, tags_to_read

=begin
  Video.check_collection event

  Video.backup_files dir_backup 

  dir_target = File.join(dir_target_parent, event.directory_name)
  Video.move_files dir_target
  event.copy_profile dir_target
=end
  
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
