#!/usr/bin/env ruby -w
# encoding: UTF-8
require_relative "anb_lib.rb"

# Video Class
class Video < ANB_exiftool

  # Testing video file
  def check opts={}
    begin
      event = opts[:event]
      dto = @metadata[:date_time_original]||@metadata[:create_date]||nil
      raise Error, "- date_time_original = 00.00.00;" unless dto
      raise Error, "- date_time_original NOT in event dates;" unless (dto >= event.date_start) and (dto <= event.date_end)

      file_format = event.options[:event][:file_format]||""
      file_format = file_format + "_" unless file_format.empty?
      # generate names
      @name_target = generate_name_target(author_nikname: event.author_nikname, date_time_original: dto, file_format: file_format)

    rescue Error => e
      add_error e.full_message(@name+@extention)
    rescue StandardError => e
      add_error e.full_backtrace_message(@name+@extention)
    end
  end #check

  # generate target name in YYYYMMDD-HHSS_AAA[AAA]_nameclean
  # To change if you have another name template
  def generate_name_target(opts={})
    # check if file already renamed to YYYYMMDD-hhss-AAA[AAA] format
    if (/^(\d{8}-\d{4}[-_]\w{3,6}[_]\w{1,13}[_])(.*)/ =~ @name)
      name_clean = $2
    elsif (/^(\d{8}-\d{6}[-_]\w{3,6}[-_ ])(.*)/ =~ @name)
      name_clean = $2
    elsif (/^(\d{8}-\d{4}[-_]\w{3,6}[-_ ])(.*)/ =~ @name)
      name_clean = $2
    # check if file already renamed in YYYYMMDD-hhss format
    elsif (/^(\d{8}-\d{4}[-_ ])(.*)/ =~ @name)
      name_clean = $2
    elsif (/^(\d{8}_)(.*)/ =~ @name)
      name_clean = $2
    # for all others just rename
    else
      name_clean = @name
    end
#    opts[:date_time_original].strftime('%Y%m%d-%H%M%S')+"_#{opts[:author_nikname]}_#{opts[:file_format]}#{name_clean}"
    opts[:date_time_original].strftime('%Y%m%d-%H%M%S')+"_#{opts[:author_nikname]} #{name_clean}"
  end

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
#  dir_to_process = Dir.pwd
  dir_backup = File.join(dir_to_process, "backup")
  dir_target_parent = "."

  event = ANB_event.new yaml_name, dir_to_process

  Video.init_collection dir_to_process, ext_to_process

  Video.batch_read_metadata dir_to_process, [:date_time_original, :create_date]

  Video.check_collection(event: event)

#  Video.backup_files dir_backup

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
