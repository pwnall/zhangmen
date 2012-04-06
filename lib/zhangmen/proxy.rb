# :nodoc: namespace
module Zhangmen
  
# Finds a HTTP proxy that will help bypass Baidu's region check.
module Proxy
  # Fresh information for a HTTP proxy in China.
  #
  # @return [String] proxy information that can be passed into the :proxy option
  #     of Zhangmen::Client#initialize
  def self.fetch
    list_url = 'http://www.xroxy.com/proxylist.php?type=Anonymous&country=CN'
    agent = Mechanize.new { |a| a.user_agent_alias = 'Linux Firefox' }
    html = agent.get_file list_url
    doc = Nokogiri.HTML html
    doc.css('table tr').each do |row|
      cells = row.css('td').map { |td| td.inner_text }
      cells.each_with_index do |cell, index|
        next unless match_data = /(\d{1,3}\.){3}\d{1,3}/.match(cell)
        ip = match_data[0]
        next unless match_data = /\d{2,5}/.match(cells[index + 1])
        port = match_data[0].to_i
        next unless match_data = /(false)|(true)/.match(cells[index + 3])
        ssl = match_data[0] == 'true'
        next if ssl
        
        return "#{ip}:#{port}"
      end
    end
  end
end  # module Zhangmen::Proxy
  
end  # namespace Zhangmen
