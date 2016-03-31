require 'rubygems'
require 'twitter'
require 'natto'

#文字数制限１４０字
TWEET_LIMIT = 140

class Tweet
  def initialize
    @text = File.open('sentences.txt').read.split("\n")
    # テキストの整形
    @text.each do |t|
      t.gsub!(/[0-9]/, "")
      t.gsub!(/『.+?』/u, "")
      t.gsub!(/（.+?）/u, "")
      t << "。" if t[-1] != "。"
    end
    @text.shuffle!

    @client = Twitter::REST::Client.new(
      consumer_key:        ENV['TWITTER_CONSUMER_KEY'],
      consumer_secret:     ENV['TWITTER_CONSUMER_SECRET'],
      access_token:        ENV['TWITTER_ACCESS_TOKEN'],
      access_token_secret: ENV['TWITTER_ACCESS_TOKEN_SECRET']
    )
    @dic = {}
    # ランダムインスタンスの生成
    @random = Random.new
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
      tweet = (tweet.length > TWEET_LIMIT) ? tweet[0,TWEET_LIMIT] : tweet
      client.update(tweet.chomp)
    rescue => e
      nil
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
    # スタートは begin,beginから
    prefix = ["BEGIN","BEGIN"]
    ss = ""
    loop do
      n = @dic[prefix].length
      prefix = [prefix[1] , @dic[prefix][@random.rand(0..n-1)]]
      ss += prefix[0] if prefix[0] != "BEGIN"
      if @dic[prefix].last == "END"
        ss += prefix[1]
        break
      end
    end
    ret = choice_sentence(ss)
    ret.gsub!(/「|」/u, " ")
    ret
  end

  def choice_sentence(ss)
    t = ss[0,TWEET_LIMIT].split('').rindex{ |c| c == "。" || c == "」" } || TWEET_LIMIT - 1
    ss[0,t+1]
  end
end
