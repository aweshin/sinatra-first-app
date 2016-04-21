require 'rubygems'
require 'twitter'
require 'natto'

#文字数制限１４０字
TWEET_LIMIT = 140
# テキストの取捨選択
SENTENCE_NO = 79..-1

class Tweet
  def initialize
    @text = File.open('sentences.txt').read.split("\n")
    # テキストの整形
    @text.each do |t|
      t.gsub!(/『.*?』/, '')
      t.gsub!(/（.*?）/u, '')
      t << '。' unless t[-1].match(/？|！|。/)
      idx = (1...t.size).each_with_object([]){ |i, acc| acc << i if t[i] == "」" && t[i-1].match(/？|！|。/) }
      idx.map.with_index{ |i,j| i + j }.each{ |i| t.insert(i, '。') }
    end
    # テキストの取捨選択
    @text = @text[SENTENCE_NO].shuffle

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

  # 形態素解析して作文する
  def random_tweet_using_mecab
    make_dic(@text)
    @dic.each_value{ |t| t.uniq! }
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

  # 辞書を元に作文を行う
  def make_sentence
    ret = choice_sentence
    # カギカッコが文の構成上おかしなことになるので、なくす
    ret.gsub!(/「|」/, '')
    # 同様に文脈がおかしくなるので、なくす
    ret.gsub!(/門番|農夫|門番、|農夫、/, '')
    # 句読点の重複排除
    ['？', '！', '。'].repeated_permutation(2) do |dw|
      ret.gsub!(dw.join, dw[0])
    end
    ret
  end

  # 文字数制限を加味する
  def choice_sentence
    loop do
      ss = connect
      # TWEET_LIMIT以内に1文がおされば
      if t = ss[0,TWEET_LIMIT].split('').rindex{ |c| c == '。' }
        return ss[0,t+1]
      end
    end
  end

  def connect
    # スタートは begin,beginから
    prefix = ['BEGIN','BEGIN']
    ss = ''
    loop do
      n = @dic[prefix].length
      prefix = [prefix[1] , @dic[prefix][@random.rand(0..n-1)]]
      ss += prefix[0] if prefix[0] != 'BEGIN'
      if @dic[prefix].last == 'END'
        ss += prefix[1]
        break
      end
    end
    ss
  end
end
