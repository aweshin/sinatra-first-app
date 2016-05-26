require 'rubygems'
require 'twitter'
require 'natto'

#文字数制限１４０字
TWEET_LIMIT = 140
# テキストの取捨選択
SENTENCE_NO = [31-1..44-1, 71-1..-1]

class Tweet
  def initialize
    raw_text = File.open('sentences.txt').read.split("\n")
    # テキストの整形
    raw_text.each do |t|
      while t.include?('（') || t.include?('）')
        t.gsub!(/（.[^（）]*?）/, '')
      end
    end
    # テキストの取捨選択
    @text = []
    SENTENCE_NO.each do |i|
      @text += raw_text[i]
    end

    @client = Twitter::REST::Client.new(
      consumer_key:        ENV['TWITTER_CONSUMER_KEY'],
      consumer_secret:     ENV['TWITTER_CONSUMER_SECRET'],
      access_token:        ENV['TWITTER_ACCESS_TOKEN'],
      access_token_secret: ENV['TWITTER_ACCESS_TOKEN_SECRET']
    )
    @dic = {}
    # ランダムインスタンスの生成
    @random = Random.new
    #ツイート数の取得
    @tweet_count = @client.user.tweets_count
  end

  def normal_tweet
    loop do
      index = (@tweet_count - 40) % @text.size
      tweet = @text[index]
      if t = check_limit(tweet)
        update(@client, tweet[0..t])
        return
      end
      index = (index + 1) % @text.size
    end
  end

  # 形態素解析して作文する
  def random_tweet_using_mecab
    @text.shuffle!
    make_dic(@text)
    tweet = choice_sentence
    update(@client, tweet)
  end

  def tweet_hybrid
    # 7割普通、 3割mecab
    @random.rand(10) > 2 ? normal_tweet : random_tweet_using_mecab
  end

  private

  # TWEET_LIMIT以内に1文以上がおさまるか
  def check_limit(tweet)
    tweet[0,TWEET_LIMIT].rindex(/。|！|？/)
  end

  def update(client, tweet)
    return nil unless tweet
    begin
      # tweet = (tweet.length > TWEET_LIMIT) ? tweet[0,TWEET_LIMIT] : tweet
      client.update(tweet.chomp)
    rescue => e
      nil
    end
  end

  # マルコフ連鎖用辞書の作成
  def make_dic(items)
    @text.each do |t|
      t.gsub!(/「|」/, '')
    end
    nm = Natto::MeCab.new
    data = ['BEGIN','BEGIN']
    @text.each do |t|
      nm.parse(t) do |a|
        if a.surface != nil
          data << a.surface
        end
      end
    end
    data << 'END'
    data.each_cons(3).each do |a|
      suffix = a.pop
      prefix = a
      @dic[prefix] ||= []
      @dic[prefix] << suffix
    end
  end

  # 辞書を元に作文を行う。文字数制限を加味する。
  def choice_sentence
    loop do
      tweet = connect
      if t = check_limit(tweet)
        return tweet[0..t]
      end
    end
  end

  def connect
    # スタートは begin,beginから
    prefix = ['BEGIN','BEGIN']
    ss = ''
    loop do
      n = @dic[prefix].length
      prefix = [prefix[1] , @dic[prefix][@random.rand(n)]]
      ss += prefix[0] if prefix[0] != 'BEGIN'
      if @dic[prefix].last == 'END'
        ss += prefix[1]
        break
      end
    end
    ss
  end
end
