require 'rubygems'
require 'twitter'
require 'natto'
require 'aws-sdk-core'
require './models/sentence.rb'

# 文字数制限140字
TWEET_LIMIT = 140
# メディアツイートの短縮URL
MEDIA_URL_LENGTH = 24
# 通常のURLの短縮版
URL_LENGTH = 23
# 重複ツイートのupload間隔(12時間)
INTERVAL = 12
# テーマの終了記号
END_OF_THEME = '─'
# MECAB_TWEETの連続数
SEQUENCE_OF_MECAB_TWEET = 2
# 再度ツイートする旧ツイートの範囲（逆数）
INV_REUSE_RANGE = 10

# mecabツイートの語尾
END_OF_MECAB_TWEET = ['なんてね', 'とか言ってみる', 'ふむふむ…',
               'パラレルワールドみたいな', 'ちょっとしたファンタジー',
               'ここから経験を立ち上げる', 'ああ…',
               'じっと手を見る', 'ことばのカタルシス', 'ちょっと危険',
               'そっとささやく', "#{(rand(1..100) ** 2) / 100}点"]
HASH_TAG = '#ほぼ駄文ですが'

class Tweet
  def initialize
    @texts = Text.all.map(&:text)

    @client = Twitter::REST::Client.new(
      consumer_key:        ENV['TWITTER_CONSUMER_KEY'],
      consumer_secret:     ENV['TWITTER_CONSUMER_SECRET'],
      access_token:        ENV['TWITTER_ACCESS_TOKEN'],
      access_token_secret: ENV['TWITTER_ACCESS_TOKEN_SECRET']
    )
  end

  def normal_tweet
    if index = next_tweet_index
      tweet = Text.find(index).text
      text = ''

      # テーマの終わり
      if delete_https(tweet)[-1] == END_OF_THEME
        theme_no = choose_next_theme(Theme.find_by("current_text_id > 0").id, Theme.where(open: true).count)
        tweet += '次は【' + theme_no.to_s + '】'
      else
        Theme.find_by("current_text_id > 0").update(current_text_id: Text.all.map(&:id).select{ |i| index < i }.min)
      end

      if Text.find(index).media
        media_tweet(MediaTweet.where(tweet_id: index).map(&:media), tweet)
      else
        # 分割ツイート
        text, tweet = split_tweet(tweet)
        update(text)
        update(tweet) unless tweet.empty?
      end
    else
      random_tweet_using_mecab
    end
  end

  # 形態素解析して作文する
  def random_tweet_using_mecab
    @texts.shuffle!
    dic = Hash.new { |hash, key| hash[key] = [] }
    make_dic(dic)
    tweet = choose_sentence(dic)
    update(tweet)
  end

  # TWEET_LIMIT以内で文章を切る。
  def from_sentence_to_tweets(text)
    # 句点（に準ずるもの）で終了していれば
    unless text.match("\n")
      return slice_text(text)
    else
      text.gsub!("\n", '。') # ダミー
      ret = slice_text(text)
      ret.map!{ |r| r.gsub('。', "\n") }
      return ret
    end
  end

  private

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

  def is_words?(text)
    !text[-1].match(/。|！|？|─/)
  end

  # 最新TWEETがそのテーマの終わりならば、SEQUENCE_OF_MECAB_TWEET分mecab_tweetし、復帰
  def next_tweet_index
    current_id =
      Theme.find_by_sql("SELECT current_text_id FROM themes WHERE current_text_id > 0").map(&:current_text_id)[0]

    if @client.user_timeline(count: SEQUENCE_OF_MECAB_TWEET).map{ |t| delete_https(t.text)[-1] == '】' }.any?
      # mecab_tweet
      return
    else
      return current_id
    end
  end

  def delete_https(tweet)
    tweet.gsub(/\s?https?.+?[\n\s　]|\s?https?.+/, '')
  end

  # 新しいテーマを決める
  def choose_next_theme(id, size)
    max_id = Theme.where(open: true).maximum(:id)
    ret = Theme.find_by(id: max_id).theme_id
    Theme.find_by("current_text_id > 0").update(current_text_id: nil)
    # データの更新
    func =
      -> theme_no { query = '【' + theme_no.to_s + '】' + '%'
        Text.find_by_sql("SELECT id FROM texts WHERE text LIKE '#{query}'").map(&:id)[0] }
    if max_id > id
      Theme.find(ret).update(current_text_id: func.call(ret))
    else
      range = size / INV_REUSE_RANGE
      ret = Theme.where(open: true).offset(rand(range)).first.theme_id
      Theme.find_by(theme_id: ret).destroy
      Theme.create({theme_id: ret, open: true, current_text_id: func.call(ret)})
    end
    ret
  end

  def media_tweet(medias, tweet)
    # AWS
    s3 = Aws::S3::Client.new
    medias.each_with_index do |media, i|
      File.open(File.basename("hoge_#{i}.png"), 'w') do |file|
        s3.get_object(bucket: ENV['S3_BUCKET_NAME'], key: "media/#{media}") do |data|
          file.write(data)
        end
      end
    end

    n = medias.size
    # 分割ツイート
    t1, t2 = split_tweet(tweet, MEDIA_URL_LENGTH * n)

    media_ids = (0...n).map{ |i| @client.upload(open("hoge_#{i}.png")) }

    if t1.length + MEDIA_URL_LENGTH * n <= TWEET_LIMIT
      # media_idsは、media_idをstring型に変換。
      # 巨大数なので、json_decodeで「x.xxE+17」というような値に変換されてしまう
      update(t1, { media_ids: media_ids.join(',') } )
      update(t2) unless t2.empty?
    else
      update(t1)
      update(t2, { media_ids: media_ids.join(',') } )
    end
  end

  # メディアツイートの文字数分減った場合、文字数制限が厳しくなる。
  def split_tweet(tweet, add_words_length = 0)
    text = ''
    text_length = 0
    loop do
      index = tweet.index(/。|！|？|──?/) || tweet.length - 1
      break if index == -1
      text_length += index + 1 + count_real_length(tweet.slice(0, index + 1))
      break if text_length > TWEET_LIMIT - add_words_length
      text += tweet.slice!(0, index + 1)
    end
    text.empty? ? [tweet, text] : [text, tweet]
  end

  def count_real_length(text)
    http_tweets = text.scan(/https?.+?[\n\s　]|https?.+/)
    http_tweets_count = http_tweets.size
    http_tweets_length = http_tweets.reduce(0){ |s, t| s + t.length - (t[-1].match(/[\n\s　]/) ? 1 : 0) }
    URL_LENGTH * http_tweets_count - http_tweets_length
  end

  def update(tweet, media = nil)
    begin
      media ? @client.update(tweet, media) : @client.update(tweet)
    rescue => e
      STDERR.puts "[EXCEPTION] " + e.to_s
      exit 1
    end
  end

  # マルコフ連鎖用辞書の作成
  def make_dic(dic)
    @texts.each do |t|
      t.gsub!(/「.+?」。?|─.+?──?|【.+?】|『.+?』|[.+?]/, '')
      t.gsub!(/「|」|（|）|"|“|”/, '')
    end
    nm = Natto::MeCab.new
    data = ['BEGIN','BEGIN']
    @texts.each do |t|
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
      dic[prefix] << suffix
    end
  end

  # 辞書を元に作文を行う。文字数制限を加味する。
  def choose_sentence(dic)
    loop do
      text = connect(dic)
      tweets = from_sentence_to_tweets(text)
      if (ret = tweets[rand(tweets.size)]).length <= TWEET_LIMIT - 3 -
        END_OF_MECAB_TWEET.map{ |t| t.length }.max - HASH_TAG.length
        return ret + "\n" + '#' + END_OF_MECAB_TWEET.sample + "\n" + HASH_TAG
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
