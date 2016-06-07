require 'rubygems'
require 'twitter'
require 'natto'

#文字数制限１４０字
TWEET_LIMIT = 140
# テキストの取捨選択
SENTENCE_NO = [1-1..-1]

WITH_MEDIA = ['─遺伝の世界とミームの世界の対応表─',
              'プロダクトデザイナー山中俊治氏の作品Ephyraは、極めて伸縮性の高いテキスタイルのロボット。Ephyraの触手は外界の環境を検知すると接触するかしないかという絶妙なタイミングで引っ込んでしまう。この動作はプログラムに従って動作しているにすぎないが、不思議と生命を感じさせる。']
MEDIA = ['gene_meme.png', 'ephyra.png']

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
    #最新のツイートを取得
    @last_tweet = @client.home_timeline(:count => 1)[0].text
  end

  def normal_tweet
    @text = @text.flat_map{ |t| check_limit(t) }
    index = @text.index(@last_tweet)
    index = @random.rand(@text.size) unless index
    tweet = @text[(index + 1) % @text.size]
    if m_index = WITH_MEDIA.index(tweet)
      begin
        @client.update_with_media(tweet, open('./photo/' + MEDIA[m_index]))
      rescue  => e
        STDERR.puts "[EXCEPTION] " + e.to_s
        exit 1
      end
    else
      update(@client, tweet)
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
  def check_limit(text)
    ret = []
    loop do
      index = text[0,TWEET_LIMIT].rindex(/。|！|？|──/)
      return ret unless index
      ret << text.slice!(0, index + 1)
    end
  end

  def update(client, tweet)
    return nil unless tweet
    begin
      # tweet = (tweet.length > TWEET_LIMIT) ? tweet[0,TWEET_LIMIT] : tweet
      client.update(tweet.chomp)
    rescue => e
      STDERR.puts "[EXCEPTION] " + e.to_s
      exit 1
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
      if (ret = check_limit(tweet)).size != 0
        return ret[@random.rand(ret.size)]
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
