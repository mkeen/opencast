require "airplay"

module Opencast
  def self.start
    yield Displays, Catalogs
    thread.join
  end
  
  def self.airplay
    @@airplay ||= Airplay::Client.new
  end
  
  def self.run_loop_iteration
    Displays.with_all do |display|
      display.default if !display.playing_video?
      display.keep_playing if display.playing_video?
    end
    
  end
  
  def self.thread
    @@thread ||= Thread.new do
      loop do
        Opencast.run_loop_iteration
        sleep 1
      end
      
    end
    
  end
  
  class Displays
    @@displays = {}
    
    class << self
      def add name, address
        @@displays[name] = Display.new address
      end
      
      def with_all
        @@displays.each do |display|
          yield display[1]
        end
        
      end
      
      def all
        @@displays
      end
      
    end
    
  end
  
  class Display
    attr_accessor :address
    
    def initialize address
      self.address = address
    end
    
    def off!
      @off = true
    end
    
    def on!
      @off = false
    end
    
    def off?
      @off == true
    end
    
    def default
      send_image 'assets/offair.jpg'
    end
    
    def playing_video?
      @playing_video == true
    end
    
    def send_image path
      Opencast.airplay.send_image path unless off?
    end
    
    def keep_playing
      Opencast.airplay.browse[0].name unless off?
    end
    
    def send_video path
      @idle = false
      @playing_video = true
      return Opencast.airplay.send_video "http://192.168.1.127:8080/#{path.split('/').last}" unless off?
      @idle = true
    end
    
  end
  
  class Catalogs
    @@catalogs = []
    
    class << self
      def add type, path
        @@catalogs << Catalog.type_instance(type, path)
      end
      
      def all
        @@catalogs
      end
      
      def shows
        @@catalogs.map do |catalog|
          catalog.shows
        end[0]
        
      end
      
      def movies
        @@catalogs.map do |catalog|
          catalog.movies
        end[0]
        
      end
      
    end
    
  end
  
  class Catalog
    attr_accessor :path
    
    class << self
      def type_instance type, path
        (Opencast.const_get "#{type.to_s.capitalize}Catalog").new path
      end
      
    end
    
    def initialize path
      @path = path
    end
    
    def shows
      (files.delete_if do |file|
        !show? file
      end).map do |show|
        Show.new show
      end
      
    end
    
    def movies
      (files.delete_if do |file|
        show? file
      end).map do |movie|
        Movie.new movie
      end
      
    end
    
    def show? file_name
      show_ident_regex =~ file_name
    end
    
    def show_ident_regex
      /[S][0-9]{2}[E][0-9]{2}/
    end
    
  end
  
  class Media
    def initialize file_name
      @file_name = file_name
    end
    
    def resolution
      return "1080p" if @file_name.include?("1080p") || @file_name.include?("1080P")
      return "720p" if @file_name.include?("720p") || @file_name.include?("720P")
      return "POOP"
    end
    
    def path
      @file_name
    end
    
    def file_name
      @file_name.split("/").last
    end
    
    def play
      Displays.all.first[1].send_video path
    end
    
  end
  
  class Movie < Media
    def initialize file_name
      super
    end
    
    def title
      s = @file_name.split('/').last.split('.')
      s.pop
      s.join(" ")
    end
    
    def dts?
      @file_name.include?("DTS") || @file_name.include?("dts")
    end
    
    def bluray?
      @file_name.include?("BluRay") || @file_name.include?("BLURAY") || @file_name.include?("bluray")
    end
    
    def info
      "#{title}"
    end
    
  end
  
  class Show < Media
    def initialize file_name
      super
      @episode = ShowEpisodeIdentifier.new file_name.split('/').last
    end
    
    def season
      @episode.season
    end
    
    def episode
      @episode.episode
    end
    
    def title
      @episode.title
    end
    
    def episodes
      Catalogs.shows.delete_if do |show|
        show.title != title
      end
      
    end
    
    def info
      "#{title} (#{episodes.count})"
    end
    
  end
  
  class ShowEpisodeIdentifier
    def initialize file_name
      @full = file_name
      @ident = @full[ident_regex =~ file_name,7]
    end
    
    def season
      season_regex.match(@ident)[1].to_i
    end
    
    def episode
      episode_regex.match(@ident)[1].to_i
    end
    
    def title
      @full[0..(ident_regex =~ @full) - 1].gsub(".", " ").strip
    end
    
    def ident_regex
      /[S][0-9]{2}[E][0-9]{2}/
    end
    
    def season_regex
      /[S]([0-9]{2})/
    end
    
    def episode_regex
      /[E]([0-9]{2})/
    end
    
  end
  
  class LocalCatalog < Catalog
    def files
      movs = []
      Dir.foreach(@path) do |filename|
        next if filename[0] == '.'
        next if !['.mp4', '.m4v'].include? filename[-4, 4]
        movs << (@path + filename)
      end
      
      movs
    end
    
  end
  
end

# Test code
Opencast.start do |display, catalog|
  display.add :livingroom, '192.168.1.102'
  catalog.add :local, '/Volumes/External/'
  
  if ARGV[0] == "shows"
    display.with_all do |d|
      d.off!
    end
    
    info = []
    Opencast::Catalogs.shows.each do |show|
      info << show.info
    end
    
    puts info.uniq.join("\n")
    Opencast.thread.kill
  end
  
  if ARGV[0] == "movies"
    display.with_all do |d|
      d.off!
    end
    
    info = []
    Opencast::Catalogs.movies.each do |movie|
      info << movie.info
    end
    
    puts info.uniq.join("\n")
    Opencast.thread.kill
  end
  
  if ARGV[0] == "broadcast"
    
  end
  
end