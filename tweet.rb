require 'rubygems'
require 'twitter'
require 'natto'

#文字数制限１４０字
TWEET_LIMIT = 140
MEDIA_URL_LENGTH = 24
# テキストの取捨選択
SENTENCE_NO = [1-1..-1]

WITH_MEDIA = ['─遺伝の世界とミームの世界の対応表─',
              'プロダクトデザイナー山中俊治氏の作品Ephyraは、極めて伸縮性の高いテキスタイルのロボット。Ephyraの触手は外界の環境を検知すると接触するかしないかという絶妙なタイミングで引っ込んでしまう。この動作はプログラムに従って動作しているにすぎないが、不思議と生命を感じさせる。',
              '『意味のメカニズム』のなかで荒川が複数回使用しているものに次のような作品がある。',
              'この自明となっていた自己の境界そのものを再度作りかえる場を形成したのが、「奈義の龍安寺・建築的身体」である。奈義町の山並みを背景として、突如斜めになった巨大な円筒が出現する。磯崎新の設計で、概観は建築物として環境の新たな再配置を実行している。',
              'この巨大な円筒形のなかに龍安寺の庭園が射影され造形されている。']
MEDIA = ['gene_meme.png', 'ephyra.png', 'arakawa1.png', 'nagi1.png', 'nagi2.png']

class Tweet
  def initialize
    raw_text = File.open('sentences.txt').read.split("\n")

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
    @last_tweet = @last_tweet[0, @last_tweet.rindex(/。|！|？|──/) + 1]
    index = @text.map{ |t| t[t.length - @last_tweet.length..-1] }.index(@last_tweet)
    index = @random.rand(@text.size) unless index
    tweet = @text[(index + 1) % @text.size]
    if m_index = WITH_MEDIA.index(tweet)
      begin
        if tweet.length <= TWEET_LIMIT - MEDIA_URL_LENGTH
          @client.update_with_media(tweet, open('./photo/' + MEDIA[m_index]))
        else
          text = ''
          while tweet.length > TWEET_LIMIT - MEDIA_URL_LENGTH
            text += tweet.slice!(0, tweet.index(/。|！|？|──/) + 1)
          end
          update(@client, text)
          @client.update_with_media(tweet, open('./photo/' + MEDIA[m_index]))
        end
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
