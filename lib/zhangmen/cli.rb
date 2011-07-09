require 'fileutils'
require 'yaml'

# :nodoc: namespace
module Zhangmen
  
# Command-line interface.
class Cli
  def scan_categories
    category_id = 1
    empty_categories = 0
    
    loop do
      begin
        playlists = @client.category category_id
        save_client_cache
        if playlists.empty?
          empty_categories += 1
          break if empty_categories == 5
        else
          empty_categories = 0
          yield category_id, playlists
        end
        category_id += 1
      rescue Exception => e
        puts "#{e.class.name}: #{e}"
        puts e.backtrace.join("\n")
        break
      end
    end
    category_id
  end
  
  def categories
    scan_categories do |id, playlists|
      puts "Category #{id}"
      playlists.each do |list|
        puts "  #{list[:name]} - #{list[:id]} - #{list[:song_count]} songs"
      end
    end
  end
  
  def playlist(list_id)
    songs = @client.playlist :id => list_id
    # save_client_cache
    
    songs.each do |song|
      print "#{song[:author]} - #{song[:title]} ... "
      bits = @client.song song
      if bits
        FileUtils.mkdir_p song[:author]
        filename = File.join song[:author],
                             "#{song[:author]} - #{song[:title]}.mp3"
        File.open filename, 'w' do |f|
          f.write bits
        end
        print "ok\n"
      else
        print "FAIL\n"
      end
    end
  end
  
  def all
    scan_categories do |id, playlists|
      puts "Category #{id}"
      playlists.each do |list|
        puts "  #{list[:name]} - #{list[:id]} - #{list[:song_count]} songs"
        playlist list[:id]
      end
    end
  end
  
  # Points to the client's metadata cache file.
  def client_cache_path
    File.expand_path '~/.zhangmen_cache'
  end
  
  # Last snapshot of the client's metadata cache.
  def client_cache
    if File.exist? client_cache_path
      YAML.load(File.read(client_cache_path)) || {} rescue {}
    else
      {}
    end
  end
  
  # Saves a new snapshot of the client's metadata cache.
  def client_cache=(new_contents)
    begin
      File.open(client_cache_path, 'w') do |f|
        YAML.dump new_contents, f
      end
    rescue ArgumentError => e
      # Encoding error; bummer, can't cache
    end
  end
  
  # Saves a new snapshot of the client's metadata cache.
  def save_client_cache
    self.client_cache = @client.cache
  end
  
  # Runs a command.
  def run(args)
    @client = Zhangmen::Client.new
    @client.cache = client_cache
    
    case args[0]
    when 'list'
      categories
    when 'fetch'
      args[1..-1].each { |arg| playlist arg }
    when 'all'
      all
    end
  end
end  # class Zhangmen::Cli

end  # namespace Zhangmen
