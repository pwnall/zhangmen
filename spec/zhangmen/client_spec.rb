# :encoding: UTF-8
require File.expand_path('../../spec_helper', __FILE__)

describe Zhangmen::Client do
  describe 'mechanizer' do
    let(:empty_client) { Zhangmen::Client.new }
    
    it 'returns a Mechanize instance' do
      empty_client.mechanizer.should be_kind_of(Mechanize)
    end
    
    describe 'with a proxy option' do
      let(:mech) do
        empty_client.mechanizer :proxy => '127.0.0.1:3306'
      end
      
      it 'parses the address correctly' do
        mech.proxy_addr.should == '127.0.0.1'
      end
      
      it 'parses the port correctly' do
        mech.proxy_port.should == 3306
      end
    end
  end

  let(:client) { Zhangmen::Client.new :proxy => ENV['http_proxy'] }
  
  describe 'op_url' do
    it 'encodes everything correctly' do
      Kernel.should_receive(:rand).and_return(0.42)
      client.op_url(22, :listid => 600).to_s.should ==
          'http://box.zhangmen.baidu.com/x?op=22&listid=600&.r=0.42' + '0' * 14
    end
  end
  
  describe 'op' do
    describe 'with good known arguments' do
      let(:result) { client.op 22, :listid => 600 }
      
      it 'returns a Nokogiri root node' do
        result.should be_kind_of(Nokogiri::XML::Element)
      end
      
      it 'returns a <result> root node' do
        result.name.should == 'result'
      end
    end
  end
  
  describe 'category' do
    describe '1' do
      let(:category) { client.category 1 }
      
      it 'should have a non-trivial number of playlists' do
        category.length.should > 10
      end
      
      it 'should have a non-empty name for each playlist' do
        category.map { |pl| pl[:name] }.any?(&:empty?).should be_false
      end

      it 'should have a non-empty download id for each playlist' do
        category.map { |pl| pl[:id] }.any?(&:empty?).should be_false
      end

      it 'should have a non-empty song count for each playlist' do
        category.map { |pl| pl[:song_count] }.any? { |count| count <= 0 }.
                 should be_false
      end
    end
  end
  
  describe 'playlist' do
    describe 'first one in category 1' do
      let(:playlist) { client.playlist client.category(1).first }
      
      it 'should have a non-trivial number of songs' do
        playlist.length.should > 10
      end
      
      it 'should have a non-empty raw name in each song' do
        playlist.map { |song| song[:raw_name] }.any?(&:empty?).should be_false
      end

      it 'should have a non-empty author in each song' do
        playlist.map { |song| song[:author] }.any?(&:empty?).should be_false
      end

      it 'should have a non-empty title in each song' do
        playlist.map { |song| song[:title] }.any?(&:empty?).should be_false
      end

      it 'should have a non-empty download id in each song' do
        playlist.map { |song| song[:id] }.any?(&:empty?).should be_false
      end
    end
  end
  
  describe 'song_sources' do
    describe 'first song in first playlits in category 1' do
      let(:sources) do
        client.song_sources client.playlist(client.category(1).first)[0]
      end
      
      it 'should have a positive number of sources' do
        sources.length.should > 0
      end
      
      it 'should have a url key in each source' do
        sources.map { |src| src[:url] }.any?(&:empty?).should be_false
      end
    end
  end
  
  describe 'song' do
    describe 'some popular song' do
      let(:entry) { client.playlist(client.category(5).first).first }
      let(:bits) { client.song entry }
      
      it 'should be a string' do
        bits.should respond_to(:to_str)
      end
      
      it 'should be more than 1Mb in size' do
        bits.length.should >= 2 ** 20
      end
    end
  end
end
