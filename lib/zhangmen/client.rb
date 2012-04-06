require 'cgi'
require 'logger'

require 'curb'
require 'hpricot'
require 'mechanize'
require 'nokogiri'

# :nodoc: namespace
module Zhangmen
  
# Wraps a client session for accessing Baidu's streaming music service.
class Client
  # New client session.
  #
  # @option options [String] proxy "host:port" string, "auto" to have a proxy
  #     discovered automatically, or nil / false to use direct requests
  # @option options [Integer] cache_ttl validity of cached requests, in seconds
  # @option options [Integer] log_level severity treshold (e.g., Logger::ERROR)
  # @option options [Logger] logger receiver of logging info
  def initialize(options = {})
    if options[:proxy] == 'auto'
      options[:proxy] = Zhangmen::Proxy.fetch
    end
    
    @mech = mechanizer options
    @curb = curber options
    @cache = {}
    @cache_ttl = options[:cache_ttl] || (24 * 60 * 60)  # 1 day
    log_level = options[:log_level] || Logger::WARN
    @logger = options[:logger] || Logger.new(STDERR)
    @logger.level = log_level
    @parser = options[:use_hpricot] ? :hpricot : :nokogiri
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
    result.search('data').map do |playlist_node|
      {
        :id => playlist_node.search('id').inner_text,
        :name => playlist_node.search('name').inner_text.encode('UTF-8'),
        :song_count => playlist_node.search('tcount').inner_text.to_i
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
    
    count = result.search('count').inner_text.to_i
    result.search('data').map do |song_node|
      raw_name = song_node.search('name').inner_text
      if match = /^(.*)\$\$(.*)\$\$\$\$/.match(raw_name)
        title = match[1].encode('UTF-8')
        author = match[2].encode('UTF-8')
      else
        author = title = raw_name.encode('UTF-8')
      end
      
      if @parser == :nokogiri
        native_encoding = result.document.encoding
      else
        native_encoding = raw_name.encoding
      end
      {
        :raw_name => raw_name.encode('UTF-8'),
        :raw_encoding => native_encoding,
        :title => title, :author => author,
        :id => song_node.search('id').inner_text
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
            expected = @curb.downloaded_content_length.to_i
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
        rescue Curl::Err::GotNothingError
          @logger.warn do
            "Server hangup fetching #{src[:url]}; got no HTTP response"
          end
          # Try again in case the error is temporary.
          sleep 1
        rescue Curl::Err::RecvError
          @logger.warn do
            "TCP error fetching #{src[:url]}"
          end
          # Try again in case the error is temporary.
          sleep 1
        rescue Timeout::Error
          @logger.warn do
            "Timeout while downloading #{src[:url]}"
          end
          # Try again in case the error is temporary.
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
    title = entry[:raw_name].encode(entry[:raw_encoding])
    result = op 12, :count => 1, :mtype => 1, :title => title, :url => '',
                    :listenreelect => 0
    result.search('url').map do |url_node|
      filename = url_node.search('decode').inner_text
      encoded_url = url_node.search('encode').inner_text
      url = File.join File.dirname(encoded_url), filename
      {
        :url => url,
        :type => url_node.search('type').inner_text.to_i,
        :lyrics_id => url_node.search('lrid').inner_text.to_i,
        :flag => url_node.search('flag').inner_text
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
    
    if @parser == :nokogiri
      Nokogiri.XML(xml).root
    else
      Hpricot(xml)
    end
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
    mech.user_agent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.124 Safari/534.30'
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
    curb.useragent = 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/534.30 (KHTML, like Gecko) Chrome/12.0.742.124 Safari/534.30'
    if options[:proxy]
      curb.proxy_url = options[:proxy]
    else
      curb.proxy_url = nil
    end
    curb
  end
end  # class Zhangmen::Client
  
end  # namespace Zhangmen
