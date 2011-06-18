require 'cgi'

require 'mechanize'
require 'nokogiri'

# :nodoc: namespace
module Zhangmen
  
# Wraps a client session for accessing Baidu's streaming music service.
class Client
  def initialize
    @mech = mechanizer
    @cache = {}
  end
  
  # Cache of HTTP requests / responses.
  #
  # The cache covers all the song metadata, but not actual song data.
  attr_accessor :cache
  
  # Fetches a collection of playlists by the category ID.
  #
  # Args:
  #   category_id:: right now, categories seem to be numbers, so enumerating
  #                 from 1 onwards should be good
  #
  # Returns an array of playlists.
  def category(category_id)
    result = op 3, :list_cat => category_id
    result.css('data').map do |playlist_node|
      {
        :id => playlist_node.css('id').inner_text,
        :name => playlist_node.css('name').inner_text.encode('UTF-8'),
        :song_count => playlist_node.css('tcount').inner_text.to_i
      }
    end
  end
  
  # Fetches a playlist.
  #
  # Args:
  #   list:: a playlist obtained by calling category
  #
  # Returns an array of songs.
  def playlist(list)
    result = op 22, :listid => list[:id]
    native_encoding = result.document.encoding
    
    count = result.css('count').inner_text.to_i
    result.css('data').map do |song_node|
      raw_name = song_node.css('name').inner_text
      if match = /^(.*)\$\$(.*)\$\$\$\$/.match(raw_name)
        title = match[1].encode('UTF-8')
        author = match[2].encode('UTF-8')
      else
        author = title = raw_name.encode('UTF-8')
      end
      
      {
        :raw_name => raw_name.encode(native_encoding),
        :title => title, :author => author,
        :id => song_node.css('id').inner_text
      }
    end
  end
  
  # Fetches the MP3 contents of a song.
  #
  # Args:
  #   song:: a song obtained by calling playlist
  #
  # Returns the MP3 bits.
  def song(entry)
    song_sources(entry).each do |src|
      3.times do
        begin
          result = @mech.get src[:url]
          next unless result.kind_of?(Mechanize::File)
          bits = result.body
          if bits[-256, 3] == 'TAG' || bits[0, 3] == 'ID3'
            return bits
          else
            break
          end
        rescue EOFError
          # Server hung up on us. Try again in case the error is temporary.
        rescue Mechanize::ResponseCodeError
          # 500-ish response. Try again in case the error is temporary.
        end 
      end
    end
    nil
  end
  
  # Fetches the MP3 download locations for a song.
  #
  # Args:
  #   song:: a song obtained by calling playlist
  #
  # Returns
  def song_sources(entry)
    result = op 12, :count => 1, :mtype => 1, :title => entry[:raw_name],
                    :url => '', :listenreelect => 0
    result.css('url').map do |url_node|
      filename = url_node.css('decode').inner_text
      encoded_url = url_node.css('encode').inner_text
      url = File.join File.dirname(encoded_url), filename
      {
        :url => url,
        :type => url_node.css('type').inner_text.to_i,
        :lyrics_id => url_node.css('lrid').inner_text.to_i,
        :flag => url_node.css('flag').inner_text
      }
    end
  end
  
  # Performs a numbered operation.
  #
  # Args:
  #   opcode:: operation number (e.g. 22 for playlist fetch)
  #   args:: operation arguments (e.g. :listid => number for playlist ID)
  #
  # Returns a Nokogiri root node.
  def op(opcode, args)
    url = op_url(opcode, args)
    cache_key = url.to_s
    @cache[cache_key] ||= @mech.get(url).body
    Nokogiri.XML(@cache[cache_key]).root
  end
  
  # The fetch URL for an XML opcode.
  def op_url(opcode, args)
    query = { :op => opcode }.merge(args).
        map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.
        join('&') + '&.r=' + ('%.16f' % Kernel.rand)
    URI.parse "http://#{hostname}/x?#{query}"
  end
  
  # The service hostname.
  def hostname
    'box.zhangmen.baidu.com'
  end
  
  # Mechanize instance customized to maximize fetch success.
  def mechanizer
    mech = Mechanize.new
    mech.user_agent_alias = 'Linux Firefox'
    mech
  end
end  # class Zhangmen::Client
  
end  # namespace Zhangmen
