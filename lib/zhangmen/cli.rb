require 'fileutils'
require 'yaml'

# :nodoc: namespace
module Zhangmen
  
# Command-line interface.
class Cli
  def scan_categories
    category_id = 1
    
    loop do
      begin
        playlists = @client.category category_id
        save_client_cache
        yield category_id, playlists
        category_id += 1
      rescue
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
  
  # Points to the client's metadata cache file.
  def client_cache_path
    File.expand_path '~/.zhangmen_cache'
  end
  
  # Last snapshot of the client's metadata cache.
  def client_cache
    if File.exist? client_cache_path
      YAML.load File.read(client_cache_path)
    else
      {}
    end
  end
  
  # Saves a new snapshot of the client's metadata cache.
  def client_cache=(new_contents)
    File.open(client_cache_path, 'w') do |f|
      YAML.dump new_contents, f
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
      playlist args[1]
    end
  end
end  # class Zhangmen::Cli

end  # namespace Zhangmen
