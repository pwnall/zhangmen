require File.expand_path('../helper.rb', File.dirname(__FILE__))

describe Zhangmen::Client do
  describe 'mechanizer' do
    let(:empty_client) { Zhangmen::Client.new }
    
    it 'returns a Mechanize instance' do
      empty_client.mechanizer.must_be_kind_of Mechanize
    end
    
    describe 'with a proxy option' do
      let(:mech) do
        empty_client.mechanizer :proxy => '127.0.0.1:3306'
      end
      
      it 'parses the address correctly' do
        mech.proxy_addr.must_equal '127.0.0.1'
      end
      
      it 'parses the port correctly' do
        mech.proxy_port.must_equal 3306
      end
    end
  end

  let(:client) { Zhangmen::Client.new :proxy => ENV['http_proxy'] || 'auto' }
  
  describe 'op_url' do
    it 'encodes everything correctly' do
      Kernel.stubs(:rand).returns(0.42)
      client.op_url(22, :listid => 600).to_s.must_equal(
          'http://box.zhangmen.baidu.com/x?op=22&listid=600&.r=0.42' + '0' * 14)
    end
  end
  
  describe 'op_cache_key' do
    it 'encodes arguments correctly' do
      client.op_cache_key(22, :listid => 600).must_equal 'listid=600&op=22'
    end
  end
  
  describe 'cache' do
    it 'behaves like a Hash' do
      client.cache.must_respond_to(:has_key?)
      client.cache.must_respond_to(:[])
      client.cache.must_respond_to(:[]=)
    end
  end
  
  describe 'op' do
    describe 'with good known arguments' do
      let(:key) { client.op_cache_key(22, :listid => 600) }
      let(:result) { client.op 22, :listid => 600 }
      
      it 'returns a Nokogiri root node' do
        result.must_be_kind_of Nokogiri::XML::Element
      end
      
      it 'returns a <result> root node' do
        result.name.must_equal 'result'
      end
      
      it 'caches the request' do
        result.wont_be_nil  # Make sure the request is performed
        client.cache.must_be :has_key?, key
        client.cache[key].must_be :has_key?, :at
        client.cache[key].must_be :has_key?, :xml
      end
      
      describe 'repeated with same arguments' do
        it 'uses the cache' do
          result.wont_be_nil # Make sure the request is performed.
          class <<client
            def op_xml_without_cache(*args)
              raise 'Cacheable request invoking un-cached code path'
            end
          end
          client.op(22, :listid => 600).wont_be_nil
        end
      end
    end
  end
  
  describe 'category' do
    describe '1' do
      let(:category) { client.category 1 }
      
      it 'has a non-trivial number of playlists' do
        category.length.must_be :>, 10
      end
      
      it 'has a non-empty name for each playlist' do
        category.map { |pl| pl[:name] }.any?(&:empty?).must_equal false
      end

      it 'has a non-empty download id for each playlist' do
        category.map { |pl| pl[:id] }.any?(&:empty?).must_equal false
      end

      it 'has a non-empty song count for each playlist' do
        category.map { |pl| pl[:song_count] }.any? { |count| count <= 0 }.
                 must_equal false
      end
    end
  end
  
  describe 'playlist' do
    describe 'first one in category 1' do
      let(:playlist) { client.playlist client.category(1).first }
      
      it 'has a non-trivial number of songs' do
        playlist.length.must_be :>, 10
      end
      
      it 'has a non-empty raw name in each song' do
        playlist.map { |song| song[:raw_name] }.any?(&:empty?).must_equal false
      end

      it 'has a non-empty author in each song' do
        playlist.map { |song| song[:author] }.any?(&:empty?).must_equal false
      end

      it 'has a non-empty title in each song' do
        playlist.map { |song| song[:title] }.any?(&:empty?).must_equal false
      end

      it 'has a non-empty download id in each song' do
        playlist.map { |song| song[:id] }.any?(&:empty?).must_equal false
      end
    end
  end
  
  describe 'song_sources' do
    describe 'first song in first playlits in category 1' do
      let(:sources) do
        client.song_sources client.playlist(client.category(1).first)[0]
      end
      
      it 'has a positive number of sources' do
        sources.length.must_be :>, 0
      end
      
      it 'has a url key in each source' do
        sources.map { |src| src[:url] }.any?(&:empty?).must_equal false
      end
    end
  end
  
  describe 'song' do
    describe 'some popular song' do
      let(:entry) { client.playlist(client.category(5).first).first }
      let(:bits) { client.song entry }
      
      it 'is a string' do
        bits.must_respond_to :to_str
      end
      
      it 'is more than 1Mb in size' do
        bits.length.must_be :>=, 2 ** 20
      end
    end
  end
end
