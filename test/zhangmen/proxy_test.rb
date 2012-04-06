require File.expand_path('../helper.rb', File.dirname(__FILE__))

describe Zhangmen::Proxy do
  describe 'fetch' do
    let(:result) { Zhangmen::Proxy.fetch }
    
    it 'matches the Zhangmen::Client :proxy format' do
      proxy_regexp = /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}\:\d{2,4}/
      result.must_match proxy_regexp 
    end
  end
end
