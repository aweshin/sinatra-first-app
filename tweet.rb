require 'rubygems'
require 'twitter'
require 'natto'

class Tweet
	def initialize
		@text = File.open('sentences.txt').read.split("\n")
		# テキストの整形
		@text.each do |t|
			t.gsub!(/[0-9]/, "")
			t.gsub!(/『.+?』/u, "")
			t.gsub!(/（.+?）/u, "")
		end
		@text.shuffle!

		@client = Twitter::REST::Client.new(
			consumer_key:        ENV['TWITTER_CONSUMER_KEY'],
			consumer_secret:     ENV['TWITTER_CONSUMER_SECRET'],
			access_token:        ENV['TWITTER_ACCESS_TOKEN'],
			access_token_secret: ENV['TWITTER_ACCESS_TOKEN_SECRET']
		)
		@dic = {}
	end

	def random_tweet
		tweet = @text[rand(@text.length)]
		update(@client, tweet)
	end

	def random_tweet_using_mecab
		# 形態素解析して作文する
		make_dic(@text)
		tweet = make_sentence
		update(@client, tweet)
	end

	private
	
	def update(client, tweet)
		return nil unless tweet
		begin
			tweet = (tweet.length > 140) ? tweet[0..139].to_s : tweet
			client.update(tweet.chomp)
		rescue => ex
			nil # todo
		end
	end

	# マルコフ連鎖用辞書の作成
	def make_dic(items)
		nm = Natto::MeCab.new
		data = ["BEGIN","BEGIN"]
		@text.each do |t|
			nm.parse(t) do |a|
				if a.surface != nil
					data << a.surface
				end
			end
		end
		data << "END"
		# p data
		data.each_cons(3).each do |a|
			suffix = a.pop
			prefix = a
			@dic[prefix] ||= []
			@dic[prefix] << suffix
		end
	end

	# 辞書を元に作文を行う
	def make_sentence
		# ランダムインスタンスの生成
		random = Random.new
		# スタートは begin,beginから
		prefix = ["BEGIN","BEGIN"]
		ret = ""
		loop do
			n = @dic[prefix].length
			prefix = [prefix[1] , @dic[prefix][random.rand(0..n-1)]]
			ret += prefix[0] if prefix[0] != "BEGIN"
			if @dic[prefix].last == "END"
				ret += prefix[1]
				break
			end
		end
		period = [-1]
		ret.length.times do |i|
			period << i if ret[i] == "。"
		end
		m = random.rand(1..period.length-1)
		ret[period[m-1]+1..period[m]]
	end
end
