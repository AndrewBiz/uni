#!/usr/bin/env ruby -w
# encoding: UTF-8

VERSION = "0.2.1" #added force dto

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
    msg = "#{self.class}: #{info} #{message}"
    msg += "BACKTRACE: #{backtrace.inspect}" if $log.debug?
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

# *** Configuration functions
class ANBConfig
  # *** Exception class ***
  class FatalError < StandardError; end
  # Find yaml file in assets directories
  def self.get_1st_yaml ypath=["."], ymask=""
    fmask = []
    ypath.each {|d| fmask << File.join(d, "#{ymask}.{yaml,yml}")}
    $log.info "* Trying to find YAML in #{fmask}"
    yaml = Dir.glob(fmask, File::FNM_CASEFOLD)[0] # 1st found file
    fail(FatalError, "No YAML file found; ") if yaml.nil?
    fail(FatalError, "- '#{yaml}' is not a file;") unless File.file?(yaml)
    yaml
  end    
end #class ANBConfig

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
  # TODO move to option_parser
  attr_reader :dir_original, :dir_tmp, :dir_target, :dir_backup, :dir_assets
  attr_reader :name_suffix_template, :name_id_template, :foto_ext
  attr_reader :force_set_dto, :delta_dto
    
  # Event data
  attr_reader :profile_name, :yaml_event
  attr_reader :prefix, :directory_name
  attr_reader :title, :date_start, :date_end, :author_nikname, :creator
  attr_reader :copyright, :keywords, :location_created, :gps_created, :collection_name, :collection_uri 
  
  # Class variables
  @@location_created_default = { :time_zone => "", :world_region => "", :country => "", :country_code => "",
      :state => "", :city => "", :location => "" }
  
  @@gps_created_default = { :gps_latitude => "", :gps_latitude_ref => "", :gps_longitude => "",
      :gps_longitude_ref => "", :gps_altitude => "", :gps_altitude_ref => "" }


  # Event initialize 
  def initialize(yaml_config, yaml_event, dir_to_process=File.pwd)
    $log.info "*** Initializing event"

    # read from config
    begin   
      yaml = yaml_config
      options_cfg = YAML.load_file(yaml)
      $log.info "YAML loaded: #{yaml}"
    rescue StandardError => e
      raise FatalError, e.full_message(" - Processing YAML #{yaml}; ")
    end

    # read from event profile
    begin   
      @yaml_event = yaml_event
      yaml = @yaml_event
      options_evt = YAML.load_file(yaml)
      $log.info "YAML loaded: #{yaml}"
    rescue StandardError => e
      raise FatalError, e.full_message(" - Processing YAML #{yaml}; ")
    end
    
    @foto_ext = options_cfg[:input_parameter][:foto_ext]||["jpg"]

    @title = options_evt[:event][:title].strip
    @collection_name = @title
    @collection_uri = options_evt[:event][:uri].strip

    #TODO put into options struct
    @name_suffix_template = options_cfg[:input_parameter][:name_suffix_template]||""
    @name_id_template = options_cfg[:input_parameter][:name_id_template]||""
    @force_set_dto = options_cfg[:input_parameter][:force_set_dto]||false
    @delta_dto = options_cfg[:input_parameter][:delta_dto]||10

    # creating array with assets directories (a-la PATH)
    @dir_assets = options_cfg[:input_parameter][:dir_assets]||[]
    @dir_assets << File.join(ENV['HOME'], File.basename($PROGRAM_NAME, File.extname($PROGRAM_NAME)))
    @dir_assets << File.dirname($PROGRAM_NAME)

    # Event dates
    begin 
      date = options_evt[:event][:date_start]||""
      @date_start = DateTime.strptime(date, $DateTimeFormat)
    rescue StandardError => e
      raise FatalError, e.full_message(" - date_start parsing error;")
    end
    begin
      date = options_evt[:event][:date_end]||""
      if date.empty?
      	# One day event
      	@date_end = DateTime.new(@date_start.year, @date_start.mon, @date_start.mday, 23, 59, 59)
      else
      	@date_end = DateTime.strptime(date, $DateTimeFormat)
      end
    rescue StandardError => e
      raise FatalError, e.full_message(" - date_end parsing error;")
    end
    
    raise FatalError, "date_end must be >= date_begin" unless  @date_end >= @date_start 
    $log.info "Event dates: #{@date_start.to_date}..#{@date_end.to_date}"
    
    @keywords = []
    kwh = options_evt[:event][:keywords]||{}
    kwh.each do |k,v|
      @keywords.concat(v)
    end  
    @keywords.uniq!
    @keywords.delete_if {|v| v.empty?}

    # creator\copyright
    alias_creator_copyright = options_evt[:event][:alias_creator_copyright]||""
    if alias_creator_copyright.empty?
      #read from event.yaml
      @author_nikname = options_evt[:event][:author_nikname]||""
      @creator = options_evt[:event][:creator]||[]
      @copyright = options_evt[:event][:copyright]||""
    else
      # read data from creators.yml
      begin
        yaml = ANBConfig.get_1st_yaml(@dir_assets, "creator*")
        creators = YAML.load_file(yaml)
        $log.info "YAML loaded: #{yaml}"
        my_creator = creators[alias_creator_copyright]
        fail(FatalError, " - No creator #{alias_creator_copyright} found in YAML #{yaml}; ") if my_creator.nil?              
        @author_nikname = my_creator[:author_nikname]||""
        @creator = my_creator[:creator]||[]
        @copyright = my_creator[:copyright]||""
      rescue ANBConfig::FatalError => e
        raise
      rescue FotoEvent::FatalError => e
        raise
      rescue StandardError => e
        raise FatalError, e.full_message(" - Parsing YAML #{yaml}; ")
      end
    end
    @copyright = "#{@date_start.year} " + @copyright

    # place_created
    alias_place_created = options_evt[:event][:alias_place_created]||""
    if alias_place_created.empty?
      #read from event.yaml
      @location_created = options_evt[:event][:location_created]||{}
      @location_created = @@location_created_default.merge @location_created
      @gps_created = options_evt[:event][:gps_created]||{}
      @gps_created = @@gps_created_default.merge @gps_created
    else
      # read data from locations.yml
      begin
        yaml = ANBConfig.get_1st_yaml(@dir_assets, "place*")
        places = YAML.load_file(yaml)
        $log.info "YAML loaded: #{yaml}"
        my_place = places[alias_place_created]
        fail(FatalError, " - No place #{alias_place_created} found in YAML #{yaml}; ") if my_place.nil?          
        @location_created = my_place[:location_created]||{}
        @location_created = @@location_created_default.merge @location_created
        @gps_created = my_place[:gps_created]||{}
        @gps_created = @@gps_created_default.merge @gps_created
  
      rescue ANBConfig::FatalError => e
        raise
      rescue FotoEvent::FatalError => e
        raise
      rescue StandardError => e
        raise FatalError, e.full_message(" - Parsing YAML #{yaml}; ")
      end
    end

    begin # create\check event directories
      @dir_original = File.expand_path(dir_to_process)

      @prefix = generate_prefix(@date_start, @date_end)
      @directory_name = "#{@prefix} #{@title}".strip

  		dir_tmp = options_cfg[:input_parameter][:dir_tmp]||DIR_TMP
      #TODO encoding in dir (UTF8 vs Win1251)
      @dir_tmp = File.expand_path(File.join(dir_tmp))
      #TODO make dir only when using it
      Dir.mkdir(@dir_tmp) unless File.exists?(@dir_tmp)

  		dir_target_parent = options_cfg[:input_parameter][:dir_target_parent]||DIR_TARGET_PARENT 
  		#TODO encoding in dir (UTF8 vs Win1251)
  		@dir_target = File.join(File.expand_path(dir_target_parent), @directory_name) 
      #TODO make dir only when using it
      Dir.mkdir(@dir_target) unless File.exists?(@dir_target)
      
  		dir_backup = options_cfg[:input_parameter][:dir_backup]||DIR_BACKUP
      #TODO encoding in dir (UTF8 vs Win1251)
      @dir_backup = File.expand_path(File.join(dir_backup))
      #TODO make dir only when using it
      Dir.mkdir(@dir_backup) unless File.exists?(@dir_backup)
      
    rescue StandardError => e
      raise FatalError, e.full_message(" - initializing event dirs; ")
    end
    $log.info "Event dir_original: #{@dir_original}"
    $log.info "Event dir_tmp: #{@dir_tmp}"
    $log.info "Event dir_target: #{@dir_target}"
    $log.info "Event dir_backup: #{@dir_backup}"
    
    begin #copy profile to target event folder
      @profile_name = File.join(@dir_target, "#{@prefix}_#{File.basename(@yaml_event)}")
      FileUtils.mv(@profile_name, @profile_name+"_backup", :force => true) if File.exists?(@profile_name)
      FileUtils.cp(@yaml_event, @profile_name)
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

  # *** ID Counter ***
  class ID_counter   
    Limit36 = "zzzzz" # zzzzz= max id during the day
    Limit_per_day = Limit36.to_i(36)
    Limit_per_sec = Limit_per_day/(24.0*3600.0)  
    attr_reader :date_init, :num, :counter
    
    def initialize
      @num = 0
      @date_init = DateTime.now
      @counter = ((@date_init.hour*3600 + @date_init.min*60 + @date_init.sec) * Limit_per_sec).to_i
    end

    def counter36
      @counter.to_s(36).upcase
    end
    
    def next
      @num += 1
      @counter += 1
      if @counter > Limit_per_day
        dn = @date_init.next 
        @date_init = DateTime.new(dn.year, dn.mon, dn.day, 0, 0, 0, dn.ofset)
        @counter = 0
      end
    end  
  end # class counter

  # Class attributes and methods
  @@llog_filename = "exiftool.log"
  @@ExifCommand = "exiftool"
  @@metadata_opts = { :creator => [], :copyright => "", :keywords => [], :location_created => {},
                      :gps_created => {}, :collection_name => "", :collection_uri => "", 
                      :force => false }
  @@collection = []
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
    Dir.mkdir(dir) unless File.exists?(dir)
  end  
  
  # Initializin foto collection
  def self.init_collection event
    msg = "*** Processing via #{__method__} ..."; puts msg; $log << "\n"; $log.info msg
    @@collection.clear

    @@id = ID_counter.new
    $log.info "Date_init=#{@@id.date_init}, Start counter=#{@@id.counter}(#{@@id.counter36})"
    
    @@current_dto2set = event.date_start
    
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
          # Force set date_time_original
          if foto.dto_need2set
            f.puts %Q{-AllDates=#{foto.date_time_original}}
          end
          
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
            f.puts %Q{-XMP:LocationCreatedWorldRegion=#{world_region}} unless world_region.empty?

            time_zone = location_created[:time_zone]||""
            # TODO time_zone

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

          # collection_name
          collection_name = opts[:collection_name]||""
          f.puts %Q{-XMP:CollectionName-=#{collection_name}}        
          f.puts %Q{-XMP:CollectionName+=#{collection_name}} 

          # collection_uri
          collection_uri = opts[:collection_uri]||""
          f.puts %Q{-XMP:CollectionURI-=#{collection_uri}}        
          f.puts %Q{-XMP:CollectionURI+=#{collection_uri}} 

          #General
          f.puts %Q{-v}

          #FIXME put UTF8 only if any IPTC tag exist to avoid creating IPTC group from scratch
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
  attr_reader :date_time_original, :dto_need2set 
  attr_accessor :errors, :metadata_conflicts
  attr_reader :backed_up, :session_id, :id36, :date_time_initialized, :author_nickname
  
  # Class constructor
  def initialize filename, event
    raise Error, "- #{filename} does not exist;" unless File.exist?(filename) 
    @errors = []
    @metadata_conflicts = [] #:creator :copyright :keywords :location_created :gps_created :collection_name :collection_uri
    @backed_up = false
    @extention = File.extname filename
    @name = File.basename filename, extention

    @filename = File.expand_path filename
    @filename_original = @filename

    @@id.next    
    @session_id = @@id.num
    @id36 = @@id.counter36

    @author_nikname = event.author_nikname
    
    # read exif info
    @date_time_original = DateTime.civil #zero date
    begin 
      exif = MiniExiftool.new filename, :timestamps => DateTime #, :convert_encoding => true
      @date_time_original = exif.date_time_original||false
      @metadata = exif.to_hash
      
      @dto_need2set = false
      unless @date_time_original
        if event.force_set_dto
          # setting dto
          @dto_need2set = true
          @date_time_original = @@current_dto2set
          @@current_dto2set += event.delta_dto*(1.0/86400) #in seconds
          $log.info "    date_time_original is forced to #{@date_time_original}"
        else  
          raise Error, "- date_time_original = 00.00.00"
        end   
      end
      
      raise Error, "- date_time_original NOT in event dates;" unless (@date_time_original >= event.date_start) and (@date_time_original <= event.date_end)
       
      # generate names
      @name_target = generate_target_name(name_suffix: event.name_suffix_template, name_id: event.name_id_template)

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
      #add_error e.full_message(name_ext)      
      add_error e.full_message(name_ext)      
    rescue Error => e
      add_error e.full_message(name_ext)      
    rescue StandardError => e
      add_error e.full_message(name_ext)
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
  # generate target name in YYYYmmdd-HHMMSS_AAA[ID]_nameclean
  # To change if you have another name template 
  def generate_target_name template={name_suffix: "", name_id: ""}

    name_prefix = %Q{#{@date_time_original.strftime('%Y%m%d-%H%M%S')}_#{@author_nikname}}

    # check if name = YYYYMMDD-hhmmss-AAA[ID]name
    if (/^(\d{8}-\d{6}_\w{3,6})(\[.*)/ =~ @name)
      return name_prefix+"#{$2}"
    end
    # check if file already renamed to YYYYMMDD-hhmm-AAA[AAA] format
    if (/^(\d{8}-\d{4}_\w{3,6}_)(.*)/ =~ @name)
      name = $2      
    elsif (/^(\d{8}-\d{4}-\w{3,6}_)(.*)/ =~ @name)
      name = $2      
    # check if file already renamed in YYYYMMDD-hhmm format                 
    elsif (/^(\d{8}-\d{4}_)(.*)/ =~ @name) 
      name = $2
    # for all others just rename
    else
      name = @name
    end

    if template[:name_id].empty?
      name_id = %Q{[#{@@id.date_init.strftime('%Y%m%d')}-#{@id36.rjust(5,"0")}]}
    else
      name_id = eval "\"#{template[:name_id]}\""
    end

    if template[:name_suffix].empty?
      suffix = "#{name}"
    else    
      suffix = eval "\"#{template[:name_suffix]}\""
    end   

    name_prefix+name_id+suffix 
  end
  
end #FotoObject class

# *** GLOBAL Constants and Variables ***
$DateTimeFormat = '%F %T'
$log = nil
