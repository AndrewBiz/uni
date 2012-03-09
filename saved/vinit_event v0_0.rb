#!/usr/bin/env ruby -w
# encoding: UTF-8
require_relative "anb_lib.rb"

# Video Class
class Video < ANB_exiftool

  # Testing video file
  def check event
    # read exif info
    begin 
      #exif = MiniExiftool.new filename, :timestamps => DateTime #, :convert_encoding => true
      dto = @metadata[:date_time_original]||@metadata[:create_date]||nil

      raise Error, "- date_time_original = 00.00.00;" unless dto 
      raise Error, "- date_time_original NOT in event dates;" unless (dto >= event.date_start) and (dto <= event.date_end)
       
      # generate names
      @name_target = generate_name_target(author_nikname: event.author_nikname, date_time_original: dto) 

    #rescue MiniExiftool::Error => e
    #  add_error e.full_backtrace_message(@name+@extention)      
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
  
  Video.batch_read_metadata dir_to_process, [:date_time_original, :create_date]

  Video.check_collection event

  Video.backup_files dir_backup 

  dir_target = File.join(dir_target_parent, event.directory_name)
  Video.move_files dir_target
  event.copy_profile dir_target
  
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
