require 'cgi'
require 'logger'

require 'curb'
require 'mechanize'
require 'nokogiri'

# :nodoc: namespace
module Zhangmen
  
# Wraps a client session for accessing Baidu's streaming music service.
class Client
  # New client session.
  #
  # The options hash accepts the following keys:
  #   :proxy:: "host:port" string
  #   :cache_ttl:: validity of cached requests, in seconds
  #   :log_level:: severity treshold (e.g., Logger::ERROR)
  #   :logger:: Logger instance to use
  def initialize(options = {})
    @mech = mechanizer options
    @curb = curber
    @cache = {}
    @cache_ttl = options[:cache_ttl] || (24 * 60 * 60)  # 1 day
    log_level = options[:log_level] || Logger::WARN
    @logger = options[:logger] || Logger.new(STDERR)
    @logger.level = log_level
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
          @curb.url = src[:url]
          begin
            @curb.perform
          rescue Curl::Err::PartialFileError
            got = @curb.body_str.length
            expected = @curb.downloaded_content_length
            if got < expected
              @logger.warn do
                "Server hangup fetching #{src[:url]}; got #{got} bytes, " +
                "expected #{expected}"
              end
              # Server gave us fewer bytes than promised in Content-Length.
              # Try again in case the error is temporary.
              sleep 1
              next
            end
          end
          next unless @curb.response_code >= 200 && @curb.response_code < 300
          bits = @curb.body_str
          if bits[-256, 3] == 'TAG' || bits[0, 3] == 'ID3'
            return bits
          else
            break
          end
        rescue Timeout::Error
          @logger.warn do
            "Timeout while downloading #{src[:url]}"
          end
          # Server hung up on us. Try again in case the error is temporary.
          sleep 1
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
    @logger.debug { "XML op #{opcode} with #{args.inspect}" }
    cache_key = op_cache_key opcode, args
    if @cache[cache_key] && Time.now.to_f - @cache[cache_key][:at] < @cache_ttl
      xml = @cache[cache_key][:xml]
      @logger.debug { "Cached response\n#{xml}" }
    else
      xml = op_xml_without_cache opcode, args
      @cache[cache_key] = { :at => Time.now.to_f, :xml => xml }
      @logger.debug { "Live response\n#{xml}" }
    end
    
    Nokogiri.XML(xml).root
  end
  
  # Performs a numbered operation, returning the raw XML.
  #
  # Accepts the same arguments as Client#op.
  #
  # Does not perform any caching.
  def op_xml_without_cache(opcode, args)
    @mech.get(op_url(opcode, args)).body
  end
  
  # A string suitable as a key for caching a numbered operation's result.
  #
  # Accepts the same arguments as Client#op.
  def op_cache_key(opcode, args)
    { :op => opcode }.merge(args).
        map { |k, v| "#{CGI.escape(k.to_s)}=#{CGI.escape(v.to_s)}" }.
        sort.join('&')
  end
  
  # The fetch URL for an XML opcode.
  #
  # Accepts the same arguments as Client#op.
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
  def mechanizer(options = {})
    mech = Mechanize.new
    mech.user_agent_alias = 'Linux Firefox'
    if options[:proxy]
      host, _, port_str = *options[:proxy].rpartition(':')
      port_str ||= 80
      mech.set_proxy host, port_str.to_i
    end
    mech
  end
  
  # Curl::Easy instance customized to maximize download success.
  def curber(options = {})
    curb = Curl::Easy.new
    curb.enable_cookies = true
    curb.follow_location = true
    curb.useragent = 'Mozilla/5.0 (X11; U; Linux i686; zh-CN; rv:1.9.2.8) Gecko/20100722 Ubuntu/10.04 (lucid) Firefox/3.6.8'
    if options[:proxy]
      curb.proxy_url = options[:proxy]
    else
      curb.proxy_url = nil
    end
    curb
  end
end  # class Zhangmen::Client
  
end  # namespace Zhangmen
