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

# 再度ツイートする旧ツイートの範囲（逆数）
INV_REUSE_RANGE = 10

# mecabツイートの語尾
# END_OF_MECAB_TWEET = ['なんてね', 'とか言ってみる', 'ふむふむ…',
#                'パラレルワールドみたいな', 'ちょっとしたファンタジー',
#                'ここから経験を立ち上げる', 'ああ…',
#                'じっと手を見る', 'ことばのカタルシス', 'ちょっと危険',
#                'そっとささやく', "#{(rand(1..100) ** 2) / 100}点"]

# MECAB_TWEETの連続数
SEQUENCE_OF_MECAB_TWEET = 1
# 大野一雄&土方巽の言葉をremixして連続ツイート
SEQUENCE_OF_KT_REMIX = 1
# HASH_TAG_MECAB = '#ほぼ駄文ですが'
HASH_TAG_KT = '#KT_REMIX'

HTTPS = /\s?https?.+?[\n\s　]|\s?https?.+/

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
    if index = next_sentence_id
      tweets = Text.where(sentence_id: index)

      # テーマの終わり
      if delete_https(tweets.last.text)[-1] == END_OF_THEME
        theme_no = choose_next_theme(Theme.find_by("current_sentence_id > 0").id, Theme.where(open: true).count)
        tweets[-1].text += '次は' + theme_no if theme_no
      else
        Theme.find_by("current_sentence_id > 0").update(current_sentence_id: Sentence.all.map(&:id).select{ |i| index < i }.min)
      end
      tweets.each do |tweet|
        t = tweet.text
        if tweet.media
          media_tweet(MediaTweet.where(tweet_id: tweet.id).map(&:media), t)
        else
          if t[-1] == '!'
          # 分割ツイート
            text1, text2 = split_tweet(t)
            update(text1)
            update(text2) unless text2.empty?
          else
            update(t)
          end
        end
      end
    else
      # random_tweet_using_mecab
      random_tweet_kt_remix
    end
  end

  # 形態素解析して作文する
  def random_tweet_using_mecab
    @texts = @texts.rotate(rand(@texts.size))[0, 100]
    dic = Hash.new { |hash, key| hash[key] = [] }
    make_dic(dic)
    tweet = choose_sentence(dic)
    update(tweet)
  end

  def random_tweet_kt_remix
    @texts = Shuffle.all.map(&:sentence)
    @texts.rotate!(rand(@texts.size))
    dic = Hash.new { |hash, key| hash[key] = [] }
    make_dic(dic)
    tweet = choose_sentence(dic)
    update(tweet)
  end

  # TWEET_LIMIT以内で文章を切る。
  def from_sentence_to_tweets(text)
    # 句点（に準ずるもの）と改行文字で文章を区切る。
    text.gsub!(/\n+\z/, '')
    text << "\n" unless text[-1] =~ /。|！|？|─/
    slice_text(text)
  end

  def ohnokazuo
    shuffles = Shuffle.all.map(&:sentence)
    @client.user_timeline("@ohnokazuo_bot", {count: 30}).map{ |t| t.text }.each do |t|
      next if t.match(HTTPS)
      unless shuffles.include?(t)
        Shuffle.create({sentence: t})
      end
    end
    @client.user_timeline("@T_Hijikata_bot", {count: 30}).map{ |t| t.text }.each do |t|
      next if t.match(HTTPS)
      unless shuffles.include?(t)
        Shuffle.create({sentence: t})
      end
    end
  end

  private

  def slice_text(text)
    ret = []
    loop do
      index = text[0,TWEET_LIMIT].rindex(/。|！|？|──|\n/)
      unless index
        # alert「141文字以上の文が含まれています」を出す。
        if text.size > TWEET_LIMIT
          return
        else
          return (text == END_OF_THEME || text.empty?) ? ret : ret << text
        end
      end
      ret << text.slice!(0, index + 1)
    end
  end

  # 最新TWEETがそのテーマの終わりならば、SEQUENCE_OF_MECAB_TWEET分mecab_tweetし、復帰
  def next_sentence_id
    current_id =
      Theme.find_by_sql("SELECT current_sentence_id FROM themes WHERE current_sentence_id > 0").map(&:current_sentence_id)[0]

    # if @client.user_timeline(count: SEQUENCE_OF_MECAB_TWEET).map{ |t| delete_https(t.text)[-1] =~ /#{END_OF_THEME}|\!/ }.any?
    if @client.user_timeline(count: SEQUENCE_OF_KT_REMIX).map{ |t| delete_https(t.text)[-1] =~ /#{END_OF_THEME}|\!/ }.any?
      # mecab_tweet
      return
    else
      return current_id
    end
  end

  def delete_https(tweet)
    tweet.gsub(HTTPS, '')
  end

  # 新しいテーマを決める
  def choose_next_theme(id, size)
    next_id = Theme.all.map(&:id).select{ |i| id < i }.min
    Theme.find_by("current_sentence_id > 0").update(current_sentence_id: nil)
    # データの更新
    func =
      -> theme_no { query = '【' + theme_no.to_s + '】' + '%'
        Sentence.find_by_sql("SELECT id FROM sentences WHERE sentence LIKE '#{query}'").map(&:id)[0] }
    if next_id
      next_theme = Theme.find(next_id).theme_id
      Theme.find_by(id: next_id).update(current_sentence_id: func.call(next_theme))
      return '【' + next_theme.to_s + '】' + 'new!'
    else
      range = size / INV_REUSE_RANGE
      next_theme = Theme.where(open: true).offset(rand(range)).first.theme_id
      Theme.find_by(theme_id: next_theme).destroy
      Theme.create({theme_id: next_theme, open: true, current_sentence_id: func.call(next_theme)})
      return
    end
  end

  def media_tweet(medias, tweet)
    # AWS
    s3 = Aws::S3::Client.new
    medias.each_with_index do |media, i|
      File.open(File.basename("hoge_#{i}.png"), 'w') do |file|
        begin
          s3.get_object(bucket: ENV['S3_BUCKET_NAME'], key: "media/#{media}") do |data|
            file.write(data)
          end
        rescue => e
          STDERR.puts "[EXCEPTION] " + e.to_s
          exit 1
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
    http_tweets = text.scan(HTTPS)
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
    # @texts.each do |t|
    #   t.gsub!(/「.+?」。?|─.+?──?|【.+?】|『.+?』|\[.+?\]/, '')
    #   t.gsub!(/「|」|（|）|"|“|”/, '')
    # end
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
      dic[prefix] << suffix unless dic[prefix].include?(suffix)
    end
  end

  # 辞書を元に作文を行う。文字数制限を加味する。
  def choose_sentence(dic)
    loop do
      text = connect(dic)
      tweets = from_sentence_to_tweets(text)
      next unless tweets
      ret = tweets.sample
      # if ret.length <= TWEET_LIMIT - 80
      #   # 吹き出しツイート
      #   ret.gsub!(/\n|\r/, '')
      #   return "＿人人人人人人人人人人人人人人＿\n" +
      #     (ret.length / 12).times.map{  '＞　' + ret.slice!(0, 12) + '　＜' }.join("\n") +
      #     "\n＞　" + ret + '　' * (12 - ret.length) + "　＜\n" +
      #     "￣Y^Y^Y^Y^Y^Y^Y^Y^Y^Y^Y^Y^Y￣\n" + HASH_TAG_MECAB
      # elsif ret.length <= TWEET_LIMIT - 3 -
      #   END_OF_MECAB_TWEET.map{ |t| t.length }.max - HASH_TAG_MECAB.length
      #   return ret + "\n" + '#' + END_OF_MECAB_TWEET.sample + "\n" + HASH_TAG_MECAB
      # end
      if ret.length <= TWEET_LIMIT - 1 - HASH_TAG_KT.length
        return ret + "\n" + HASH_TAG_KT
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
