#!/usr/bin/env ruby -w
# encoding: UTF-8
# ANB Foto Library
require "rubygems"
require "yaml"
require "date"
require "logger"
require "fileutils"
require_relative "mini_exiftool_fork" # gem install mini_exiftool (http://miniexiftool.rubyforge.org/)
require_relative "progressbar" 
# require "progressbar" # gem install progressbar (https://github.com/jfelchner/ruby-progressbar)
#TODO optionparser

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

  end #add

end  #Class ANBLogger

# *** Read input params
def read_input_params
  #utility sub
  def find_first_yaml_file(dir_to_process)
    Dir.chdir(dir_to_process)
    yaml_file = nil
    Dir.glob("*.yaml") do |file|
      yaml_file = file
      break
    end  
    return yaml_file
  end

  # read input args
  dir_to_process = ARGV[0]||Dir.pwd
  fail("#{dir_to_process} does not exist") unless File.exist?(dir_to_process) 
  fail("#{dir_to_process} is not a Directory") unless File.directory?(dir_to_process)
  $log.info "Dir to be processed: #{dir_to_process}"
  
  yaml_name = ARGV[1]||find_first_yaml_file(dir_to_process)
  fail("- no YAML File found;") if yaml_name.nil?  
  fail("- no YAML File found;") unless File.file?(yaml_name)
  $log.info "YAML Profile to be processed: #{yaml_name}"
  return [dir_to_process, yaml_name]
end

# *** Foto event ***
class FotoEvent
  # *** Constants 
  # Желательно, чтобы dir_* были в ASCII иначе - несовместимость с Windows
  DIR_TMP = "tmp"
  DIR_TARGET_PARENT = "."
  DIR_BACKUP = "backup"

  # *** Exception class ***
  class FatalError < StandardError; end

  # Instance attributes and methods
  attr_reader :options
  attr_reader :profile_name
  attr_reader :dir_original, :dir_tmp, :dir_target, :dir_backup, :name_suffix_template  
  attr_reader :foto_ext, :prefix, :directory_name
  attr_reader :title, :date_start, :date_end, :time_zone, :author_nikname, :creator
  attr_reader :copyright, :keywords, :location_created, :gps_created 
  
  # Class variables
  @@location_created_default = { :world_region => "", :country => "", :country_code => "",
      :state => "", :city => "", :location => "" }
  
  @@gps_created_default = { :gps_latitude => "", :gps_latitude_ref => "", :gps_longitude => "",
      :gps_longitude_ref => "", :gps_altitude => "", :gps_altitude_ref => "" }
  
  # Event initialize 
  def initialize(yaml_name, dir_to_process=File.pwd)
    $log.info "*** Initializing event"
    # read script_options fromm profile
    begin
      @options = YAML.load_file(yaml_name)
      $log.info "YAML loaded: #{yaml_name}"
    rescue StandardError => e
      raise FatalError, e.full_message(" - Parsing YAML #{yaml_name}; "), e.backtrace
    end
    
    @foto_ext = @options[:input_parameter][:foto_ext]||["jpg"]
    #TODO Check not empty ??
    @title = @options[:event][:title].strip
    @name_suffix_template = @options[:event][:name_suffix_template]||""
    
    # Event dates
    begin 
      @date_start = DateTime.strptime(@options[:event][:date_start], $DateTimeFormat)
    rescue StandardError => e
      raise FatalError, e.full_message(" - date_start parsing error;"), e.backtrace
    end
    begin
      @date_end = DateTime.strptime(@options[:event][:date_end], $DateTimeFormat)
    rescue StandardError => e
      raise FatalError, e.full_message(" - date_end parsing error;"), e.backtrace
    end
    
    raise FatalError, "date_end must be >= date_begin" unless  @date_end >= @date_start 
    $log.info "Event dates: #{@date_start.to_date}..#{@date_end.to_date}"
    
    @time_zone = @options[:event][:time_zone]||""

    @author_nikname = @options[:event][:author_nikname]||""
    @creator = @options[:event][:creator]||[]
    
    @keywords = []
    kwh = @options[:event][:keywords]||{}
    kwh.each do |k,v|
      @keywords.concat(v)
    end  
    @keywords.uniq!
    @keywords.delete_if {|v| v.empty?}
    
    @copyright = @options[:event][:copyright]||""
    
    @location_created = @options[:event][:location_created]||{}
    @location_created = @@location_created_default.merge @location_created
    
    @gps_created = @options[:event][:gps_created]||{}
    @gps_created = @@gps_created_default.merge @gps_created
    
    begin # create\check event directories
      @dir_original = File.expand_path(dir_to_process)

      @prefix = generate_prefix(@date_start, @date_end)
      @directory_name = "#{@prefix} #{@title}".strip

  		dir_tmp = @options[:input_parameter][:dir_tmp]||DIR_TMP
      #TODO encoding in dir (UTF8 vs Win1251)
      @dir_tmp = File.expand_path(File.join(dir_tmp))
      Dir.mkdir(@dir_tmp) unless File.exists?(@dir_tmp)

  		dir_target_parent = @options[:input_parameter][:dir_target_parent]||DIR_TARGET_PARENT 
  		#TODO encoding in dir (UTF8 vs Win1251)
  		@dir_target = File.join(File.expand_path(dir_target_parent), @directory_name) 
      Dir.mkdir(@dir_target) unless File.exists?(@dir_target)
      
  		dir_backup = @options[:input_parameter][:dir_backup]||DIR_BACKUP
      #TODO encoding in dir (UTF8 vs Win1251)
      @dir_backup = File.expand_path(File.join(dir_backup))
      Dir.mkdir(@dir_backup) unless File.exists?(@dir_backup)
      
    rescue StandardError => e
      raise FatalError, e.full_message(" - initializing event dirs; "), e.backtrace
    end
    $log.info "Event dir_original: #{@dir_original}"
    $log.info "Event dir_tmp: #{@dir_tmp}"
    $log.info "Event dir_target: #{@dir_target}"
    $log.info "Event dir_backup: #{@dir_backup}"
    
    begin #copy profile to target event folder
      @profile_name = File.join(@dir_target, "#{@prefix}_event_profile.yaml")
      FileUtils.mv(@profile_name, @profile_name+"_backup", :force => true) if File.exists?(@profile_name)
      FileUtils.cp(yaml_name, @profile_name)
    rescue => e
      raise FatalError, " - copying profile to target event dir;"
    end
    $log.info "Event profile: #{@profile_name}"
    $log.info "*** Event initialized Ok"
  end #initialize
  
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

# *** Foto object ***
class FotoObject
  # *** Exception class ***
  class Error < StandardError; end

  # Class attributes and methods
  @@llog_filename = "exiftool.log"
  @@ExifCommand = "exiftool"
  @@metadata_opts = { :creator => [], :copyright => "", :keywords => [], :location_created => {},
                      :gps_created => {}, :collection_name => [], :collection_uri => [], 
                      :force => false }
  @@collection = []
  @@current_id = 0
  @@errors_occured = false
  @@metadata_conflicts_occured = false

  def self.collection
    @@collection
  end
  def self.errors_occured
    @@errors_occured
  end
  def self.metadata_conflicts_occured
    @@metadata_conflicts_occured
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
  
  # Initializin foto collection
  def self.init_collection event
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    @@collection.clear
    @@current_id = 0
    @@errors_occured = false
    @@metadata_conflicts_occured = false
    Dir.chdir(event.dir_original)
    fmask = "*.{#{event.foto_ext * ","}}"
    $log.info "Initial scan DIR: #{event.dir_original}, MASK: #{fmask}"
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
      self.new(file, event)
      pbar.inc
    end #glob
    pbar.finish
    $stderr.puts "! Some files have metadata conflicts. See log" if @@metadata_conflicts_occured
    $log.info "*** TOTAL files initialized: #{@@collection.count}"
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

  # batch fix dto time_zone
  def self.batch_fix_time_zone(dir)
  #TODO  
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    $log.info "*** processed:"
  end

  # batch set metadata tags
  def self.batch_set_tags(dir=File.pwd, opts={})
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    opts = @@metadata_opts.merge opts
    Dir.chdir(dir)
    $log.info "*** Setting metadata tags in #{dir}"
    if self.collection_real_size <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end
    llog = ANBLogger.new(@@llog_filename)
 
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
          $log.info "    Tags already exist: #{foto.metadata_conflicts.inspect}" unless foto.metadata_conflicts.empty? 
          f.puts %Q{# #{total}}
          
          # TODO force
          if foto.metadata_conflicts.index(:creator).nil?
            # MWG:Creator = EXIF:Artist, IPTC:By-line, XMP-dc:Creator
            creator = opts[:creator]||[]
            creator.each do |o| 
              f.puts %Q{-MWG:Creator-=#{o}}
              f.puts %Q{-MWG:Creator+=#{o}}
            end 
          end 

          if foto.metadata_conflicts.index(:copyright).nil?
            # MWG:Copyright = EXIF:Copyright, IPTC:CopyrightNotice, XMP-dc:Rights
            copyright = opts[:copyright]||""
            f.puts %Q{-MWG:Copyright=#{copyright}} unless copyright.empty?
          end 

          #disabled check: if foto.metadata_conflicts.index(:keywords).nil?
          # MWG:Keywords = IPTC:Keywords, XMP-dc:Subject
          keywords = opts[:keywords]||[]
          keywords.each do |o|
            f.puts %Q{-MWG:Keywords-=#{o}}        
            f.puts %Q{-MWG:Keywords+=#{o}} 
          end

          if foto.metadata_conflicts.index(:location_created).nil?
            # MWG:Country, State, City, Location
            location_created = opts[:location_created]||{}

            world_region = location_created[:world_region]||""
            #0 TODO!    

            country = location_created[:country]||"" #1 MWG:Country Страна
            f.puts %Q{-MWG:Country=#{country}} unless country.empty?
            
            country_code = location_created[:country_code]||"" #1 XMP-iptcCore:CountryCode ISO_3166-1
            f.puts %Q{-XMP-iptcCore:CountryCode=#{country_code}} unless country_code.empty?

            state = location_created[:state]||"" #2 MWG:State  Регион, область
            f.puts %Q{-MWG:State=#{state}} unless state.empty?
            
            city = location_created[:city]||""  #3 MWG:City  Город
            f.puts %Q{-MWG:City=#{city}} unless city.empty?

            location = location_created[:location]||"" #4 MWG:Location - Район, местность
            f.puts %Q{-MWG:Location=#{location}} unless location.empty?
          end 

          if foto.metadata_conflicts.index(:gps_created).nil?
            # GPS
            gps_created = opts[:gps_created]||{}     
            
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
          end 
          #TODO mwg-coll:CollectionName :collection_name
          #TODO mwg-coll:CollectionURI :collection_uri

          #General
          f.puts %Q{-v}

          #TODO put UTF8 only if any IPTC tag exist to avoid creating IPTC group from scratch
          f.puts %Q{-IPTC:CodedCharacterSet=UTF8}
          
          f.puts %Q{-EXIF:ModifyDate=now}

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
  end # set_tags

  # batch set metadata tags
  def self.batch_fix_fmd dir
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    Dir.chdir(dir)
    dir = File.expand_path(dir)
    $log.info "*** Setting metadata tags in #{dir}"
    collection_real_size = self.collection_real_size
    if collection_real_size <= 0
      msg = "*** #{__method__}: Nothing to process"; $log.warn msg
      return   
    end
    llog = ANBLogger.new(@@llog_filename)

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
      
  # Instance attributes and methods
  attr_reader :filename, :filename_original, :metadata
  attr_reader :name, :name_target, :extention
  attr_accessor :date_time_original, :file_modify_date, :errors, :metadata_conflicts
  attr_reader :backed_up, :session_id, :date_time_initialized, :author_nickname
  
  # Class constructor
  def initialize filename, event
    raise Error, "- #{filename} does not exist;" unless File.exist?(filename) 
    @errors = []
    @metadata_conflicts = [] #:creator :copyright :keywords :location_created :gps_created :collection_name :collection_uri
    @backed_up = false
    @extention = File.extname filename
    @name = File.basename filename, extention
    #TODO! check double names!    

    @filename = File.expand_path filename
    @filename_original = @filename
    
    @date_time_initialized = DateTime.now
    @session_id = @@current_id; @@current_id += 1
    
    @author_nikname = event.author_nikname
    
    # read exif info
    @date_time_original = DateTime.civil #zero date
    @file_modify_date = DateTime.civil
    begin 
      exif = MiniExiftool.new filename, :timestamps => DateTime #, :convert_encoding => true
      @date_time_original = exif.date_time_original||false
      @file_modify_date = exif.file_modify_date||false
      @metadata = exif.to_hash

      raise Error, "- date_time_original = 00.00.00;" unless @date_time_original 
      raise Error, "- date_time_original NOT in event dates;" unless (@date_time_original >= event.date_start) and (@date_time_original <= event.date_end)
       
      # generate names
      @name_target = generate_target_name event.name_suffix_template

      # check existing metadata
      #puts %Q{Creator=#{exif.Creator}}
      val = exif.Creator||[]
      add_metadata_conflict("   #{name_ext} has value in tag ", :creator,
          [%Q{Creator=#{exif.Creator}}]) unless val.empty?

      #puts %Q{Copyright=#{exif.Copyright}}
      val = exif.Copyright||""
      add_metadata_conflict("   #{name_ext} has value in tag ", :copyright,
          [%Q{Copyright=#{exif.Copyright}}]) unless val.empty?

      # $log.debug %Q{Subject=#{exif.Subject}}
      # val = exif.Keywords||[] (mini_exiftool do not read composite tag)
      val = exif.Subject||[]
      add_metadata_conflict("   #{name_ext} has value in tag ", :keywords,
          [%Q{Keywords=#{val}}]) unless val.empty?

      #puts %Q{Country=#{exif.Country}}
      #puts %Q{CountryCode=#{exif.CountryCode}}
      #puts %Q{State=#{exif.State}}
      #puts %Q{City=#{exif.City}}
      #puts %Q{Location=#{exif.Location}}
      val = exif.Country||exif.CountryCode||exif.State||exif.City||exif.Location||""
      add_metadata_conflict("   #{name_ext} has value in tag ", :location_created,
          [%Q{Country=#{exif.Country}}, %Q{CountryCode=#{exif.CountryCode}}, %Q{State=#{exif.State}},
           %Q{City=#{exif.City}}, %Q{Location=#{exif.Location}}]) unless val.empty?

      #puts %Q{GPSLatitude=#{exif.GPSLatitude}}
      #puts %Q{GPSLongitude=#{exif.GPSLongitude}}
      val = exif.GPSLatitude||exif.GPSLongitude||""
      add_metadata_conflict("   #{name_ext} has value in tag ", :gps_created,
          [%Q{GPSLatitude=#{exif.GPSLatitude}}, %Q{GPSLongitude=#{exif.GPSLongitude}}]    
          ) unless val.empty?

      #TODO check :collection_name :collection_uri

    rescue MiniExiftool::Error => e
      add_error e.full_message(name_ext)      
      #add_error e.full_backtrace_message(name_ext)      
    rescue Error => e
      add_error e.full_message(name_ext)      
    rescue StandardError => e
      add_error e.full_backtrace_message(name_ext)
    end
    
    @@collection << self
  end #initialize

  # generate file name with extention
  def name_ext
  	@name+@extention
  end

  # foto backup
  def backup dir_backup=nil
    return true if @backed_up
    @backed_up = false
    return false if dir_backup.nil?
    begin
      filename_backup = File.join(dir_backup, name_ext)
      FileUtils.cp(@filename_original, filename_backup)
    rescue StandardError => e
      add_error e.full_message(name_ext) 
      @backed_up = false 
    else
      @backed_up = true
    end
    @backed_up
  end

  # foto rename to target
  def move_to dir=nil
    #TODO chmod!!!, работа с флагами
    return false if dir.nil?
    
    filename_target = File.join(dir, @name_target+@extention)
    return true if filename_target == @filename # already moved

    begin
      FileUtils.mv(@filename, filename_target) 
    rescue StandardError => e
      add_error e.full_message(name_ext) 
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
    @@metadata_conflicts_occured = true
    @metadata_conflicts << metadata_name
  end  
    
  private
  # generate target name in YYYYMMDD-HHSS_AAA[AAA]_nameclean
  # To change if you have another name template 
  def generate_target_name name_suffix_template
    name_prefix = %Q{#{@date_time_original.strftime('%Y%m%d-%H%M%S')}_#{@author_nikname}}
    name_id = %Q{[#{@date_time_initialized.strftime('%Y%m%d-%H%M%S')}-#{sprintf("%03d", @session_id)[-3,3]}]}
    # check if name = YYYYMMDD-hhmmss-AAA[ID]name
    if (/^(\d{8}-\d{6}_\w{3,6})(\[.*)/ =~ @name)
      return name_prefix+"#{$2}"
    end
    # check if file already renamed to YYYYMMDD-hhmm-AAA[AAA] format
    if (/^(\d{8}-\d{4}_\w{3,6}_)(.*)/ =~ @name)
      name = $2      
    # check if file already renamed in YYYYMMDD-hhmm format                 
    elsif (/^(\d{8}-\d{4}_)(.*)/ =~ @name) 
      name = $2
    # for all others just rename
    else
      name = @name
    end
    if name_suffix_template.empty?
        suffix = "#{name}"
    else    
      suffix = eval "\"#{name_suffix_template}\""
    end   
    return name_prefix+name_id+suffix 
  end
  
end #FotoObject class

# *** GLOBAL Constants and Variables ***
$DateTimeFormat = '%F %T'
$log = nil
