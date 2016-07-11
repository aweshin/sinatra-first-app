require 'rubygems'
require 'twitter'
require 'natto'

# 文字数制限140字
TWEET_LIMIT = 140
# メディアツイートの短縮URL
MEDIA_URL_LENGTH = 24
# 重複ツイートのupload間隔(12時間)
INTERVAL = 12
# テーマの終了記号
END_OF_THEME = '─'
# MECAB_TWEETの連続数
SEQUENCE_OF_MECAB_TWEET = 2

SENTENCE_NO = [18..42, 44..45, 56..60, 62..68, 99..99, 106..106, 112..117, 139..-1]
# mecabツイートの語尾
END_OF_MECAB_TWEET = ['なんてね', 'とか言ってみる', 'ふむふむ…',
               'パラレルワールドみたいな', 'ちょっとしたファンタジー',
               'ここから経験を立ち上げる', '…ああ',
               'じっと手を見る', 'ことばのカタルシス', 'ちょっと危険',
               'そっとささやく', "#{(rand(1..100) ** 2) / 100}点"]
HASH_TAG = ' #ほぼ駄文ですが'
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
              'オパビニア',
              'D.リンチ”Red Headed Party Doll”',
              'F.ベーコン”Head IV”']
MEDIA = ['gene_meme.png',
         'wingsuits.png',
         'arakawa_1.png',
         'nagi_1.png',
         'nagi_2.png',
         'musicBottles.png',
         'sublimate.png',
         'bacon.png',
         'reversible_fig.gif',
         'ancient_creatures.jpg',
         'lynch.png',
         'bacon_2.png']

class Tweet
  def initialize
    sentences = File.open('./sentences.txt').read.split("\n")

    text = []
    SENTENCE_NO.each do |i|
      text += sentences[i]
    end
    @text = join_text(text.flat_map{ |t| from_text_to_tweets(t) })

    @client = Twitter::REST::Client.new(
      consumer_key:        ENV['TWITTER_CONSUMER_KEY'],
      consumer_secret:     ENV['TWITTER_CONSUMER_SECRET'],
      access_token:        ENV['TWITTER_ACCESS_TOKEN'],
      access_token_secret: ENV['TWITTER_ACCESS_TOKEN_SECRET']
    )
  end

  def normal_tweet
    if index = last_tweet_index
      tweet = @text[(index + 1) % @text.size]
      text = ''
      # テーマの終わり
      if delete_https(tweet)[-1] == END_OF_THEME
        tweet += '次は【' + next_theme.to_s + '】'
      end
      # メディアツイート
      if media_indexes = WITH_MEDIA.map.with_index{ |t, i| i if tweet.include?(t) }.compact
        # 分割ツイート
        text, tweet = split_tweet(tweet, MEDIA_URL_LENGTH)
        update(text) unless text.empty?
        # 最新ツイートがメディアのみの場合を考慮
        tweet = '《こちら》' if tweet.empty?
        media_ids = media_indexes.map{ |i| @client.upload(open('./media/' + MEDIA[i])) }
        update(tweet, { media_ids : media_ids.join(',') } )
      else
        # 分割ツイート
        text, tweet = split_tweet(tweet)
        update(text) unless text.empty?
        update(tweet)
      end
    else
      random_tweet_using_mecab
    end
  end

  # 形態素解析して作文する
  def random_tweet_using_mecab
    @text.shuffle!
    dic = {}
    make_dic(dic)
    tweet = choice_sentence(dic)
    update(tweet)
  end

  private

  # TWEET_LIMIT以内で文章を切る。
  def from_text_to_tweets(text)
    text.slice!(text.rindex(/（/)..-1) if text[-1] == '）'
    # 句点（に準ずるもの）で終了していれば
    if text[-1].match(/。|！|？|─/)
      return slice_text(text)
    else
      text += '。' # ダミー
      ret = slice_text(text)
      ret[-1].slice!(-1)
      return ret
    end
  end

  def slice_text(text)
    ret = []
    loop do
      index = text[0,TWEET_LIMIT].rindex(/。|！|？|──/)
      unless index
        ret << text unless text == END_OF_THEME || text.empty?
        return ret
      end
      ret << text.slice!(0, index + 1)
    end
  end

  def join_text(text)
    ret = [text.shift]
    text.each do |t|
      # 前の文章が句読点で終わっていない、かつ、次の文章を足しても文字数が超過しなければ
      if is_words?(ret.last) && ret.last.length + t.length <= TWEET_LIMIT
        ret[-1] += "\n" + t
      else
        ret << t
      end
    end
    ret
  end

  def is_words?(text)
    !text[-1].match(/。|！|？|─/)
  end

  # 最新TWEETがそのテーマの終わりならば、SEQUENCE_OF_MECAB_TWEET分mecab_tweetし、復帰
  def last_tweet_index
    tweets = @client.home_timeline(:count => SEQUENCE_OF_MECAB_TWEET + 1)
    last_tweet = tweets[0].text
    indexes = tweets.map{ |tw|
      tw = delete_https(tw.text).gsub(/次は【\d+】/, '')
      @text.index{ |t| t.include?(tw) }
    }
    index = indexes[0]
    # メディアツイートを考慮
    if delete_https(last_tweet) == '《こちら》'
      index = indexes[1]
    end
    # mecab_tweetの開始
    return if index && last_tweet[-1] == '】'

    # 復帰
    unless indexes[0, SEQUENCE_OF_MECAB_TWEET].any?
      index = @text.index{ |t| t.include?(find_number(tweets)) } - 1
    end
    index
  end

  def delete_https(tweet)
    tweet.gsub(/\s?https?.+?──|\s?https?.+─?/, '')
  end

  # 番号付けされたテーマの番号を直近のツイートから追跡
  def find_number(tweets)
    tweets.each do |tw|
      if number = tw.text.slice(-5, 5).match(/\d+】/)
        return '【' + number.to_s
      end
    end
  end

  # 新しいテーマを決める
  def next_theme
    # 最新400件にツイートされていないテーマを選ぶ
    theme_numbers = @text.map{ |t|
      md = t.match(/【(\d+)】/)
      md[1].to_i if md
    }.compact
    timeline = @client.home_timeline(:count => 200)
    maxid = 0
    2.times do
      timeline.each do |tw|
        md = tw.text.slice(0, 6).match(/【(\d+)】/)
        theme_numbers.delete(md[1].to_i) if md
        maxid = tw.id - 1
      end
      timeline = @client.home_timeline(:count => 200, :max_id => maxid)
    end
    theme_numbers.sample
  end

  # メディアツイートの文字数分減った場合、文字数制限が厳しくなる。
  def split_tweet(tweet, add_words_length = 0)
    text = ''
    while tweet.length > TWEET_LIMIT - add_words_length
      text += tweet.slice!(0, tweet.index(/。|！|？|──?/) + 1)
    end
    [text, tweet]
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
  def make_dic(dic)
    @text.each do |t|
      t.gsub!(/「.+?」。?|─.+?──?|【.+?】|『.+?』|[.+?]/, '')
      t.gsub!(/「|」|（|）|"|“|”/, '')
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
      dic[prefix] ||= []
      dic[prefix] << suffix
    end
  end

  # 辞書を元に作文を行う。文字数制限を加味する。
  def choice_sentence(dic)
    loop do
      text = connect(dic)
      tweets = from_text_to_tweets(text)
      if (ret = tweets[rand(tweets.size)]).length <= TWEET_LIMIT - 2 -
        END_OF_MECAB_TWEET.map{ |t| t.length }.max - HASH_TAG.length
        return ret + ' #' + END_OF_MECAB_TWEET.sample + HASH_TAG
      end
    end
  end

  def connect(dic)
    # スタートは begin,beginから
    prefix = ['BEGIN','BEGIN']
    ret = ''
    loop do
      n = dic[prefix].length
      prefix = [prefix[1] , dic[prefix][rand(n)]]
      ret += prefix[0] if prefix[0] != 'BEGIN'
      if dic[prefix].last == 'END'
        ret += prefix[1]
        break
      end
    end
    ret
  end
end
