#!/usr/bin/env ruby -w
# encoding: UTF-8
# ANB Foto Library
require "rubygems"
require "yaml"
require "json"
require "date"
require "logger"
require "fileutils"
require_relative "mini_exiftool_fork" # gem install mini_exiftool (http://miniexiftool.rubyforge.org/)
require_relative "progressbar" 

# *** Standard Ruby class - anb alter ***
class Exception
  def full_message(info=nil)
    "#{self.class}: #{info} #{message}"
  end
  def full_backtrace_message(info=nil)
    msg = "#{self.class}: #{info} #{message}"
    msg += ". Backtrace: #{backtrace.inspect}" if $log.debug?
    return  msg
  end
end

# *** Standard Ruby class - anb alter ***
class ANBLogger < Logger
  attr_reader :logdev
  # improved method add - put message into $stderr
  def add(severity, message = nil, progname = nil, &block)
    if message.nil?
      if block_given?
        msg = yield
      else
        msg = progname
      end
    end

    case severity
      #when WARN
      #	$stderr.puts "WARN: #{msg}"
      #	$stderr.puts	
    when ERROR
      $stderr.puts "ERROR: #{msg}"
      $stderr.puts	
    when FATAL
      $stderr.puts "FATAL: #{msg}"
      $stderr.puts
    end
    super
  end
end  #Class ANBLogger

# *** Read input params
def read_input_params options_cli={}
  #utility sub
  def find_first_yaml_file(dir_to_process)
    Dir.chdir(dir_to_process)
    yaml_file = nil
    Dir.glob("*.{yaml,yml}") do |file|
      yaml_file = file
      break
    end  
    return yaml_file
  end

  # read input args
  dir_to_process = Dir.pwd
  fail("#{dir_to_process} does not exist") unless File.exist?(dir_to_process) 
  fail("#{dir_to_process} is not a Directory") unless File.directory?(dir_to_process)
  $log.info "Dir to be processed: #{dir_to_process}"
  
  yaml_name = options_cli['--event']||find_first_yaml_file(dir_to_process)
  fail("- no YAML File found;") if yaml_name.nil?  
  fail("- no YAML File found;") unless File.file?(yaml_name)
  $log.info "YAML Profile to be processed: #{yaml_name}"
  return [dir_to_process, yaml_name]
end

# !!! *** Input Parameters ***
class Parameters
  # *** Exception class ***
  class FatalError < StandardError; end

  # Instance attributes and methods
  attr_reader :options
  attr_reader :profile_name
  attr_reader :dir_original, :dir_tmp, :dir_backup, :dir_target  
  attr_reader :file_ext
    
  # params initialize 
  def initialize(yaml_name, dir_to_process=File.pwd)
    $log.info "*** Initializing parameters"
    # read script_options from profile
    begin
      @options = YAML.load_file(yaml_name)
      $log.info "YAML loaded: #{yaml_name}"
    rescue StandardError => e
      raise FatalError, e.full_message(" - Parsing YAML #{yaml_name}; "), e.backtrace
    end
  
    @file_ext = @options[:input_parameter][:file_ext]||["jpg"]          

    begin # create\check directories
      @dir_original = File.expand_path(dir_to_process)
  		@dir_tmp = @options[:input_parameter][:dir_tmp]||""
  		@dir_backup = @options[:input_parameter][:dir_backup]||"" 
  		@dir_target = @options[:input_parameter][:dir_target]||""
    rescue StandardError => e
      raise FatalError, e.full_message(" - initializing params dirs; "), e.backtrace
    end    
    $log.info "*** Parameters initialized Ok"
  end #initialize
  
end # class

# *** Universal event description***
class ANB_event

  # *** Exception class ***
  class FatalError < StandardError; end

  # Instance attributes and methods
  attr_reader :yaml_name, :options, :profile_name
  attr_reader :dir_original, :directory_name
  attr_reader :title, :date_start, :date_end, :time_zone, :author_nikname, :creator
  attr_reader :copyright, :keywords, :location_created, :gps_created 
  
  # Class variables
  @@location_created_default = { :world_region => "", :country => "", :country_code => "",
      :state => "", :city => "", :location => "" }
  
  @@gps_created_default = { :gps_latitude => "", :gps_latitude_ref => "", :gps_longitude => "",
      :gps_longitude_ref => "", :gps_altitude => "", :gps_altitude_ref => "" }
  
  # Event initialize 
  def initialize(yaml_name, dir_to_process=Dir.pwd, options_cli)
    $log.info "*** Initializing event"
    # read script_options from profile
    begin
      @options = YAML.load_file(yaml_name)
      $log.info "YAML loaded: #{yaml_name}"
    rescue StandardError => e
      raise FatalError, e.full_message(" - Parsing YAML #{yaml_name}; "), e.backtrace
    end
    @yaml_name = yaml_name

    @title = @options[:event][:title].strip
    
    # +Event dates
    begin 
      @date_start = DateTime.strptime(@options[:event][:date_start], $DateTimeFormat)
      @date_end = DateTime.strptime(@options[:event][:date_end], $DateTimeFormat)
    rescue StandardError => e
      raise FatalError, e.full_message(" - Event dates parsing error;"), e.backtrace
    end
    
    raise FatalError, "date_end must be >= date_begin" unless  @date_end >= @date_start 
    $log.info "Event dates: #{@date_start.to_date}..#{@date_end.to_date}"
    
    @time_zone = @options[:event][:time_zone]||""

    @author_nikname = options_cli['--author']||@options[:event][:author_nikname]||""
    @creator = @options[:event][:creator]||[]
    
    @keywords = @options[:event][:keywords]||[]
    @copyright = @options[:event][:copyright]||""
    
    @location_created = @options[:event][:location_created]||{}
    @location_created = @@location_created_default.merge @location_created
    
    @gps_created = @options[:event][:gps_created]||{}
    @gps_created = @@gps_created_default.merge @gps_created
    
    begin # create\check event directories
      @dir_original = File.expand_path(dir_to_process)
      prefix = generate_prefix(@date_start, @date_end)
      @directory_name = "#{prefix} #{@title}".strip
    rescue StandardError => e
      raise FatalError, e.full_message(" - initializing event dirs; "), e.backtrace
    end

    @profile_name = "#{prefix}_event.yml"
    $log.info "*** Event initialized Ok"
  end #initialize
  
  # Copy profile
  def copy_profile dir
    begin #copy profile to target event folder
      Dir.chdir @dir_original
      file_name = File.join(dir, @profile_name)
      FileUtils.cp(@yaml_name, file_name)
    rescue => e
      raise FatalError, e.full_message(" - copying profile to target event dir;"), e.backtrace
    end
  end

  private
  # Generate PREFIX in format:
  #     YYYYmmdd if date1 == date2
  #     YYYYmmdd-dd if day is different
  #     YYYYmmdd-mmdd if month is different
  #     YYYYmmdd-YYYYmmdd if year is different
  def generate_prefix(date1, date2)
    prefix = date1.strftime('%Y%m%d')
    return prefix += "-"+date2.strftime('%Y%m%d') if date1.year != date2.year
    return prefix += "-"+date2.strftime('%m%d') if date1.mon != date2.mon
    return prefix += "-"+date2.strftime('%d') if date1.mday != date2.mday
    return prefix
  end
end # class

# *** ToolBox ***
class ANB_exiftool
	# Constants
 	TAGS = { date_time_original: {aliases: ["DateTimeOriginal", "H264:DateTimeOriginal"], type: :date_time},
 					 create_date: {aliases: ["CreateDate", "QuickTime:CreateDate"], type: :date_time},
 					 keywords: {aliases: ["MWG:Keywords", "Composite:Keywords"], type: :array_string} }

  # *** Exception class ***
  class Error < StandardError; end

  # Class attributes and methods
  @@llog_filename = "exiftool.log"
  @@ExifCommand = "exiftool"
  @@metadata_opts = { :creator => [], :copyright => "", :keywords => [], :location_created => {},
                      :gps_created => {}, :collection_name => [], :collection_uri => [], 
                      :force => false }
  @@collection = []
  @@errors_occured = false

  # self.accessors
  def self.collection
    @@collection
  end
  def self.errors_occured
    @@errors_occured
  end
  
  # Collection size - only clean items count (no errors)
  def self.collection_real_size
    size = 0
    @@collection.each_index do |i|
      foto = @@collection[i]
      size += 1 if foto.errors.empty?
    end
    return size
  end

  # mkdir
  def self.make_dir dir
    #TODO encoding in dir (UTF8 vs Win1251)
    Dir.mkdir(dir) unless File.exists?(dir)
  end  
 
  # Initializin collection
  def self.init_collection dir=Dir.pwd, file_ext=[jpg]
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    @@collection.clear
    @@errors_occured = false
    Dir.chdir(dir)
    fmask = "*.{#{file_ext * ","}}"
    $log.info "*** Initial scan DIR: #{dir}, MASK: #{fmask}"
    # fake loop - to count files
    files2process = 0
    Dir.glob(fmask, File::FNM_CASEFOLD) do |file|
      files2process += 1
    end
    if files2process <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end
    # real loop
    msg = "Files to process: #{files2process}"; $log.info msg
    pbar = ProgressBar.new("Initial scan", files2process)
    Dir.glob(fmask, File::FNM_CASEFOLD) do |file|
      $log.info "Initializing #{file}"
      self.new file
      pbar.inc
    end #glob
    pbar.finish
    $log.info "*** TOTAL files initialized: #{@@collection.count}"
  end

  # conversion
  def self.convert_tag tag_val=nil, tag_type=:string
    return nil if tag_val.nil?
    case tag_type
	  when :date_time then 
	    return DateTime.strptime(tag_val, $DateTimeFormat) 
	  when :array_string then 
	  	return tag_val #TODO 
	  when :string then 
	  	return tag_val
	  else 
	  	return nil
    end    
  end #convert_tag

  # batch read metadata tags
  def self.batch_read_metadata dir=Dir.pwd, tags_to_read = [:date_time_original]
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    Dir.chdir(dir)
    dir = File.expand_path(dir)
    $log.info "*** Setting metadata tags in #{dir}"
    if self.collection_real_size <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end
    # generate exiftool command
    args = ["-json", "-G"]
    args << %Q{-d} 
    args << %Q{%Y-%m-%d %H:%M:%S}
    tags_to_read.each do |t|
    	fail("Tag to read: #{t} is not valid") if TAGS[t].nil?
    	args << %Q{-#{TAGS[t][:aliases][0]}}
    end

    items2process = 0
    @@collection.each do |o|
      if o.errors.empty?
      	items2process += 1            
        args << %Q{#{o.name+o.extention}}
      end 
    end
    
    # generate json via exiftool
    json_name = "metadata.json"
    File.open(json_name, "w+") do |f|
      msg = "*** Running #{@@ExifCommand} #{args*" "}"; $log.info msg 
      begin
        result = system(@@ExifCommand, *args, {:out=>f})
        raise Error if result.nil?
      rescue => e
        msg = e.full_message("#{__method__} - fail to execute #{@@ExifCommand};"); $log.error msg
      end
      msg = "*** Result: #{result||"fail"}, #{$?}"; $log.info msg
    end   

    # parse json
    begin
      serialized = File.read(json_name)
      md_all = JSON.parse(serialized)
    rescue => e
      msg = e.full_message("#{__method__} - fail to parse json"); $log.error msg
    end
    metadata_all ={}
    md_all.each do |mdf|
      filename = mdf.delete("SourceFile")||"not_found.ext"
      extention = File.extname filename
      name = File.basename filename, extention
      metadata_all[name] = mdf
    end  

    # map collection vs metadata_all
    @@collection.each do |o|
      begin
        metadata_raw = metadata_all[o.name]||{}
        # read all tags for given object
        tags_to_read.each do |tag|
          tag_val = nil
        	TAGS[tag][:aliases].each do |tag_alias|
        	  tag_val ||= metadata_raw[tag_alias]
        	end
        	# tag type conversion    	
        	o.metadata[tag] = convert_tag tag_val, TAGS[tag][:type]   
        end    
      rescue => e
        o.add_error e.full_message(o.name+o.extention)
      end       
    end # o    
  end #self.batch_set_dates_smart

  # Testing collection
  def self.check_collection opts
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    
    if self.collection_real_size <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end
    pbar = ProgressBar.new("Checking", @@collection.count)
    total = 0
    @@collection.each do |item|
      if  item.errors.empty?
        total += 1
        $log.info "Checking #{item.name+item.extention}"
        item.check opts
      else
        $log.info "Skipping #{item.name+item.extention} due to errors(#{item.errors.size}) found before"
      end
      pbar.inc
    end
    pbar.finish
    $log.info "*** TOTAL files processed: #{total}"
  end

  # Batch backup files
  def self.backup_files dir=""
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    if dir.empty?
      msg = "*** #{__method__}: Directory is not set"; $log.warn msg
      return
    else
      self.make_dir dir
      $log.info "*** Backing up files to #{dir}"
    end  
    
    if self.collection_real_size <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end
    pbar = ProgressBar.new("Backing up", @@collection.count)
    total = 0
    ok = 0
    @@collection.each do |foto|
      if  foto.errors.empty?
        total += 1
        $log.info "Backing up #{foto.name+foto.extention}"
        result_ok = foto.backup dir
        if result_ok
        	ok += 1
        	$log.info "  OK"
        end
      else
        $log.info "Skipping #{foto.name+foto.extention} due to errors(#{foto.errors.size}) found before"
      end
      pbar.inc
    end
    pbar.finish
    $log.info "*** TOTAL files processed: #{total}, backed up Ok: #{ok}"
  end #self.backup_files

  # Batch move files
  def self.move_files dir=""
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    if dir.empty?
      msg = "*** #{__method__}: Directory is not set"; $log.warn msg
      return
    else
      self.make_dir dir
      $log.info "*** Moving files to #{dir}"
    end  
    
    if self.collection_real_size <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end
    pbar = ProgressBar.new("Moving", @@collection.count)
    total = 0
    ok = 0
    @@collection.each do |foto|
      if  foto.errors.empty?
        total += 1
        $log.info "Moving #{foto.name+foto.extention}"
        result_ok = foto.move_to dir
        if result_ok
        	ok += 1
        	$log.info "  OK"
        end
      else
        $log.info "Skipping #{foto.name+foto.extention} due to errors(#{foto.errors.size}) found before"
      end
      pbar.inc
    end
    pbar.finish
    $log.info "*** TOTAL files processed: #{total}, moved Ok: #{ok}"
  end #self.move_files

  # batch set metadata tags
  def self.batch_set_dates_smart(dir=Dir.pwd, date2set=nil, delta=0)
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    Dir.chdir(dir)
    dir = File.expand_path(dir)
    llog = ANBLogger.new(@@llog_filename)
    $log.info "*** Setting metadata tags in #{dir}"
    if self.collection_real_size <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end
    # generate exiftool command
    cdate = date2set
    script_name = "#{__method__}.txt"
    args = ["-@", script_name]
     
    # generate ARGFILE for exiftool
    total = 0
    File.open(script_name, "w+") do |f|
      f.puts %Q{# #{@@ExifCommand} #{args*" "}}
      pbar = ProgressBar.new("Preparing", @@collection.count)
      @@collection.each do |foto|
        if  foto.errors.empty?
          total += 1
          $log.info "Adding #{foto.name+foto.extention} to script"
          f.puts %Q{# #{total}}
          
          f.puts %Q{-AllDates="#{cdate.strftime($DateTimeFormat)}"}
          
          #General
          f.puts %Q{-v}
          f.puts %Q{-ignoreMinorErrors}
          f.puts %Q{-EXIF:ModifyDate="#{Time.now.strftime($DateTimeFormat)}"}

          f.puts %Q{-P}
          f.puts %Q{-overwrite_original}

          f.puts %Q{#{foto.name+foto.extention}}
          f.puts %Q{-execute} 
          f.puts
          cdate += delta*(1.0/1440)
        else
          $log.info "Skipping #{foto.name+foto.extention} due to errors(#{foto.errors.size}) found before"
        end
        pbar.inc
      end
      pbar.finish
      $log.info "*** TOTAL files processed: #{total}"
    end # generate ARGFILE
    
    self.run_command args, llog

    llog.close
  end #self.batch_set_dates_smart

  # batch set metadata tags
  def self.batch_set_gps(dir, gps_created, force=false)
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    Dir.chdir(dir)
    dir = File.expand_path(dir)
    llog = ANBLogger.new(@@llog_filename)
    $log.info "*** Setting metadata tags in #{dir}"
    collection_real_size = self.collection_real_size
    if collection_real_size <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end

    # generate exiftool command
    script_name = "#{__method__}.txt"
    args = ["-@", script_name]

    # generate ARGFILE for exiftool
    total = 0
    File.open(script_name, "w+") do |f|
      f.puts %Q{# #{@@ExifCommand} #{args*" "}}
      pbar = ProgressBar.new("Preparing", @@collection.count)
      @@collection.each do |foto|
        if  foto.errors.empty?
          total += 1
          $log.info "Adding #{foto.name+foto.extention} to script"
          f.puts %Q{# #{total}}
          # GPS
          
          f.puts %Q{-if} unless force
          f.puts %Q{not GPSPosition} unless force
         
          gps_latitude = gps_created[:gps_latitude]||""
          gps_latitude_ref = gps_created[:gps_latitude_ref]||""
          if not gps_latitude.empty? and not gps_latitude_ref.empty?
            f.puts %Q{-GPSLatitude="#{gps_latitude}"}       
            f.puts %Q{-GPSLatitudeRef=#{gps_latitude_ref}}
          end
          
          gps_longitude = gps_created[:gps_longitude]||""
          gps_longitude_ref = gps_created[:gps_longitude_ref]||""
          if not gps_longitude.empty? and not gps_longitude_ref.empty?
            f.puts %Q{-GPSLongitude="#{gps_longitude}"}      
            f.puts %Q{-GPSLongitudeRef=#{gps_longitude_ref}}
          end
            
          gps_altitude = gps_created[:gps_altitude].to_f||0.0
          gps_altitude_ref = gps_created[:gps_altitude_ref]||""
          if not gps_altitude_ref.empty?
            f.puts %Q{-GPSAltitude=#{gps_altitude}}      
            f.puts %Q{-GPSAltitudeRef=#{gps_altitude_ref}}
          end  
          
          #General
          f.puts %Q{-v}
          f.puts %Q{-EXIF:ModifyDate="#{Time.now.strftime($DateTimeFormat)}"}
          f.puts %Q{-P}
          f.puts %Q{-overwrite_original}
          f.puts %Q{-ignoreMinorErrors}

          f.puts %Q{#{foto.name+foto.extention}}
          f.puts %Q{-execute} 
          f.puts
        else
          $log.info "Skipping #{foto.name+foto.extention} due to errors(#{foto.errors.size}) found before"
        end
        pbar.inc
      end
      pbar.finish
      $log.info "*** TOTAL files processed: #{total}"
    end # generate ARGFILE

    self.run_command args, llog

    llog.close
  end #batch_set_gps

  # batch set metadata tags
  def self.batch_fix_fmd dir
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    Dir.chdir(dir)
    dir = File.expand_path(dir)
    llog = ANBLogger.new(@@llog_filename)
    $log.info "*** Setting metadata tags in #{dir}"
    collection_real_size = self.collection_real_size
    if collection_real_size <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end

    # generate exiftool command
    script_name = "#{__method__}.txt"
    args = ["-@", script_name]
     
    # generate ARGFILE for exiftool
    total = 0
    File.open(script_name, "w+") do |f|
      f.puts %Q{# #{@@ExifCommand} #{args*" "}}
      pbar = ProgressBar.new("Preparing", @@collection.count)
      @@collection.each do |foto|
        if  foto.errors.empty?
          total += 1
          $log.info "Adding #{foto.name+foto.extention} to script"
          f.puts %Q{# #{total}}
          
          #General
          f.puts %Q{-v}
          f.puts %Q{-overwrite_original}
          f.puts %Q{-DateTimeOriginal>FileModifyDate}
          f.puts %Q{-ignoreMinorErrors}
          f.puts %Q{#{foto.name+foto.extention}}
          f.puts %Q{-execute} 
          f.puts
        else
          $log.info "Skipping #{foto.name+foto.extention} due to errors(#{foto.errors.size}) found before"
        end
        pbar.inc
      end
      pbar.finish
      $log.info "*** TOTAL files processed: #{total}"
    end # generate ARGFILE

    self.run_command args, llog

    llog.close
  end #batch_fix_fmd

  # Run sexiftool command
  def self.run_command args, llog
    msg = "*** Running #{@@ExifCommand} #{args*" "}"
    $log.info msg; llog << "\n"; llog.info msg    
    begin
      result = system(@@ExifCommand, *args, { :out=>llog.logdev.dev}) #:chdir=>dir,, :err=>llog.logdev.dev
      raise Error if result.nil?
    rescue => e
      msg = e.full_message("#{__method__} - fail to execute #{@@ExifCommand};"); $log.error msg
    end      
    msg = "*** Result: #{result||"fail"}, #{$?}"; $log.info msg; llog.info msg
  end #run_command
  
  # Instance attributes and methods
  attr_reader :filename, :filename_original
  attr_reader :name, :name_clean, :name_target, :extention
  attr_accessor :metadata, :errors, :metadata_conflicts
  attr_accessor :date_time_original
  attr_reader :backed_up
  
  # Class constructor
  def initialize filename
    raise Error, "- #{filename} does not exist;" unless File.exist?(filename) 
    @metadata = {}
    @errors = []
    @metadata_conflicts = [] #:creator :copyright :keywords
    #:location_created :gps_created :collection_name :collection_uri
    @backed_up = false
    @extention = File.extname filename
    @name = File.basename filename, extention
    @name_target = @name
    @filename = File.expand_path filename
    @filename_original = @filename
    @date_time_original = nil #DateTime.civil #zero date
    @@collection << self
  end #initialize
  
  # foto backup
  def backup dir=""
    return true if @backed_up
    @backed_up = false
    return false if dir.empty?
    begin
      filename_backup = File.join(dir, @name+@extention)
      FileUtils.cp(@filename_original, filename_backup)
    rescue StandardError => e
      add_error e.full_message(@name+@extention) 
      @backed_up = false 
    else
      @backed_up = true
    end
    @backed_up
  end

  # foto rename to target
  def move_to dir=""
    #TODO chmod!!!, работа с флагами
    return false if dir.empty?
    
    filename_target = File.join(dir, @name_target+@extention)

    begin
      FileUtils.mv(@filename, filename_target) 
    rescue StandardError => e
      add_error e.full_message(@name+@extention) 
      return false 
    else
      @filename = filename_target
      @name = @name_target
      return true
    end
  end  

  # register error 
  def add_error message
    $log.error message
    @@errors_occured = true
    @errors << message
  end  

  # register metadata_conflict 
  def add_metadata_conflict message, metadata_name, metadata_values=[]
    $log.warn %Q{#{message} #{metadata_name}}
    $log.info %Q{      Values: #{metadata_values.inspect}} 
    @metadata_conflicts << metadata_name
  end  

  # generate target name in YYYYMMDD-HHSS_AAA[AAA]_nameclean
  # To change if you have another name template 
  def generate_name_target(opts={})
    # check if file already renamed to YYYYMMDD-hhss-AAA[AAA] format
    if (/^(\d{8}-\d{4}_\w{3,6}_)(.*)/ =~ @name)
      name_clean = $2      
    # check if file already renamed in YYYYMMDD-hhss format                 
    elsif (/^(\d{8}-\d{4}_)(.*)/ =~ @name) 
      name_clean = $2
    # for all others just rename
    else
      name_clean = @name
    end
    return opts[:date_time_original].strftime('%Y%m%d-%H%M')+"_#{opts[:author_nikname]}_#{name_clean}" 
  end

end #ANB_exiftool class

# *** GLOBAL Constants and Variables ***
$DateTimeFormat = '%F %T'
$log = nil
