require 'rubygems'
require 'twitter'
require 'natto'

# 文字数制限140字
TWEET_LIMIT = 140
# メディアツイートの短縮URL
MEDIA_URL_LENGTH = 24
# 重複ツイートのupload間隔
INTERVAL = 12
# テーマの終了記号
END_OF_THEME = '─'
# MECAB_TWEETの連続数
SEQUENCE_OF_MECAB_TWEET = 3
# テキストの取捨選択
SENTENCE_NO = [32..42, 44..45, 62..68, 99..99, 106..106, 112..117, 139..-1]
# mecabツイートの語尾
END_OF_MECAB_TWEET = ['なんてね。', 'とか言ってみる。', 'ふむふむ…',
               '(ry', '経験のパラレルワールド。', 'ちょっとしたファンタジー。',
               'からの経験の立ち上げ。', '…ああ。',
               'じっと手を見る。', 'ことばのカタルシス。', 'ちょっと危険。',
               'そっとささやく。', "#{(rand(1..100) ** 2) / 100}点。"]
# メディアツイート
WITH_MEDIA = ['遺伝の世界とミームの世界の対応表',
              'Wingsuits',
              '『意味のメカニズム』のなかで荒川が複数回使用しているものに',
              '奈義町の山並みを背景として、突如斜めになった巨大な円筒が出現する。',
              'この巨大な円筒形のなかに龍安寺の庭園が射影され造形されている。',
              'music bottles',
              'sublimate',
              'フランシス・ベーコン',
              '反転図形から反転図形',
              'オパビニア']
MEDIA = ['gene_meme.png',
         'wingsuits.png',
         'arakawa_1.png',
         'nagi_1.png',
         'nagi_2.png',
         'musicBottles.png',
         'sublimate.png',
         'bacon.png',
         'reversible_fig.gif',
         'ancient_creatures.jpg']

class Tweet
  def initialize
    raw_text = File.open('./sentences.txt').read.split("\n")

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
    # 過去200件のツイートを取得
    @last_200_tweets = @client.home_timeline(:count => 200)
    @last_tweet = @last_200_tweets[0].text
  end

  def normal_tweet
    if index = tweet_index
      tweet = @text[(index + 1) % @text.size]
      if media_index = WITH_MEDIA.index{ |t| tweet.include?(t) }
        # メディアツイート
        text, tweet = split_tweet(tweet)
        # 分割ツイート
        update(text) unless text.empty?
        update(tweet, open('./media/' + MEDIA[media_index]))
      else
        update(tweet)
      end
    end
  end

  # 形態素解析して作文する
  def random_tweet_using_mecab
    @text.shuffle!
    make_dic
    tweet = choice_sentence
    update(tweet)
  end

  private

  # 最新TWEETがそのテーマの終わりならば、SEQUENCE_OF_MECAB_TWEET分MECAB_TWEETし、復帰
  def tweet_index
    @text = @text.flat_map{ |t| check_limit(t) }
    @text = join_text(@text)
    indexes = @last_200_tweets[0,SEQUENCE_OF_MECAB_TWEET].map{ |tw|
      tw = delete_https(tw.text)
      @text.index{ |t| t.include?(tw) }
    }
    index = indexes[0]
    unless index
      unless indexes.any?
        # 新しいテーマを決める
        index = next_theme
      else
        random_tweet_using_mecab
        return
      end
    else
      if delete_https(@last_tweet)[-1] == END_OF_THEME
        random_tweet_using_mecab
        return
      end
    end
    index
  end

  # TWEET_LIMIT以内に1文以上がおさまるか
  def check_limit(text)
    ret = []
    loop do
      index = text[0,TWEET_LIMIT].rindex(/。|！|？|──/)
      unless index
        if ret.empty?
          return text.gsub(/（.+?）/, '')
        else
          return ret
        end
      end
      ret << text.slice!(0, index + 1)
    end
  end

  def join_text(text)
    ret = [text.shift]
    text.each do |t|
      if ret.last.size + t.size <= TWEET_LIMIT &&
        !(ret.last[-1].match(/。|！|？|─/))
        ret[-1] = [ret.last, t].join("\n")
      else
        ret << t
      end
    end
    ret
  end

  def delete_https(tweet)
    tweet.gsub(/\s?https?.+?──|\s?https?.+─?/, '')
  end

  def next_theme
    indexes = @text.map.with_index{ |t, i|
      i if delete_https(t)[-1] == END_OF_THEME }.compact
    # 最新200件にツイートされていないテーマを選ぶ
    list = @last_200_tweets.map{ |tw|
      tw = delete_https(tw.text)
      @text.index{ |t| t.include?(tw) } if tw[-1] == END_OF_THEME
    }.compact
    # １つ前のテーマの最後のインデックスを消す（前から見た次のテーマ＝該当するテーマ）
    (indexes - list.map{ |index| indexes[indexes.index(index) - 1] }).sample
  end

  # メディアツイートの文字数分減った場合、文字数制限が厳しくなる。
  def split_tweet(tweet)
    ret = ''
    while tweet.length > TWEET_LIMIT - MEDIA_URL_LENGTH
      ret += tweet.slice!(0, tweet.index(/。|！|？|──?/) + 1)
    end
    tweet = 'こちら' if tweet.empty?
    [ret, tweet]
  end

  def update(tweet, media = nil)
    begin
      if media
        @client.update_with_media(tweet, media)
      else
        @client.update(tweet)
      end
    rescue => e
      STDERR.puts "[EXCEPTION] " + e.to_s
      exit 1
    end
  end

  # マルコフ連鎖用辞書の作成
  def make_dic
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
      text = connect
      tweets = check_limit(text)
      if tweets.instance_of?(Array) &&
        (ret = tweets[@random.rand(tweets.size)]).length <=
        TWEET_LIMIT - END_OF_MECAB_TWEET.max_by{ |t| t.length }.length
        return ret + END_OF_MECAB_TWEET.sample
      end
    end
  end

  def connect
    # スタートは begin,beginから
    prefix = ['BEGIN','BEGIN']
    ret = ''
    loop do
      n = @dic[prefix].length
      prefix = [prefix[1] , @dic[prefix][@random.rand(n)]]
      ret += prefix[0] if prefix[0] != 'BEGIN'
      if @dic[prefix].last == 'END'
        ret += prefix[1]
        break
      end
    end
    ret
  end
end
