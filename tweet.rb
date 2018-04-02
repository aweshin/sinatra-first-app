require 'rubygems'
require 'twitter'
require 'natto'
require 'aws-sdk-core'
require './models/sentence.rb'
require 'json'
require 'uri'


class Tweet
  attr_reader :client, :end_of_theme

  def initialize
    @texts = Text.all.map(&:text)

    @client = Twitter::REST::Client.new(
      consumer_key:        ENV['TWITTER_CONSUMER_KEY'],
      consumer_secret:     ENV['TWITTER_CONSUMER_SECRET'],
      access_token:        ENV['TWITTER_ACCESS_TOKEN'],
      access_token_secret: ENV['TWITTER_ACCESS_TOKEN_SECRET']
    )

    config = open('./config/config_tweet.json') do |io|
      JSON.load(io)
    end

    @tweet_limit = config["ツイート文字数制限"].to_i
    @url_length = config["リンクのURLの短縮版"].to_i
    @end_of_theme = config["テーマの終了記号"]
    @inv_reuse_range = config["再度ツイートする旧ツイートの範囲（逆数）"].to_i
    @sequence_of_remix = config["random_tweet_remixの連続数"].to_i
    @hash_tag_remix = config["random_tweet_remixのセルフハッシュタグ"]
    @mention_tweet_remix = "@" + ENV['RANDOM_TWEET_REMIX']
    @remix_tweets = config["random_tweet_remixのmecab辞書登録数"].to_i
    @limit_of_sequence_of_texts = config["テーマごとのツイート登録数の上限数"].to_i
  end

  def normal_tweet
    if index = next_sentence_id
      tweets = Text.where(sentence_id: index).order("id")

      # テーマの終わり
      if delete_https(tweets.last.text)[-1] == @end_of_theme
        theme_no = choose_next_theme(Theme.find_by("current_sentence_id > 0").id, Theme.where(open: true).count)
        tweets[-1].text += '次は' + theme_no if theme_no
      else
        Theme.find_by("current_sentence_id > 0").update(current_sentence_id: Text.all.map(&:sentence_id).select{ |i| index < i }.min)
      end
      tweets.each do |tweet|
        t = tweet.text
        # 2017/11/08 - Twitterが文字数制限を緩和。日本語は140文字制限のままだが、半角英数字や記号を含む場合、その部分は「1文字」ではなく「0.5文字」とカウントされるようになった。
        flag = true if downsize_unless_japanese(t) > @tweet_limit
        # 分割ツイート
        text1, text2 = split_tweet(t) if flag

        # リプライツイート
        if t[0] == '【' # テーマのはじめ
          # nothing
        else
          in_reply_to_status_id = @client.user_timeline(count: 1)[0].id
        end

        if tweet.media
          medias = MediaTweet.where(tweet_id: tweet.id).map(&:media)
        end

        if in_reply_to_status_id || medias
          if flag
            extra_tweet(text1, medias, in_reply_to_status_id)
            extra_tweet(text2, medias, in_reply_to_status_id) unless text2.empty?
          else
            extra_tweet(t, medias, in_reply_to_status_id)
          end
        else
          if flag
            update(text1)
            update(text2) unless text2.empty?
          else
            update(t)
          end
        end
      end
    else
      random_tweet_remix
    end
  end

  # @tweet_limit以内で文章を切る。
  def from_sentence_to_tweets(text)
    # 句点（に準ずるもの）と改行文字で文章を区切る。
    text.gsub!(/\n+\z/, '')
    # text << "\n" unless text[-1] =~ /[。？\?！\!#{@end_of_theme}]/
    slice_text(text)
  end

  # 形態素解析して作文する
  def random_tweet_remix
    @texts = Shuffle.all.map(&:sentence).sample(@remix_tweets)
    dic = Hash.new { |hash, key| hash[key] = [] }
    make_dic(dic)
    # 詩系は句点削除
    tweet1, tweet2 = choose_sentence(dic)
    update(tweet1)
    update(tweet2, { in_reply_to_status_id: @client.user_timeline(count: 1)[0].id }) if tweet2
  end

  def delete_https(tweet)
    tweet.gsub(/[…\s]/, '').gsub(URI.regexp(%w[http https]), '')
  end

  private

  def slice_text(sentence)
    ret = []
    loop do
      text = ''
      text_length = 0
      loop do
        index = sentence.index(/。|！|？|\?|\!|#{@end_of_theme}#{@end_of_theme}|\n/)
        unless index
          if downsize_unless_japanese(sentence) > @tweet_limit
            # alert「141文字以上の文が含まれています」を出す。
            return
          else
            if sentence == @end_of_theme || sentence.empty?
              return (text == @end_of_theme || text.empty? ) ? ret : ret << text
            else
              if text_length + downsize_unless_japanese(sentence) > @tweet_limit
                ret << text
                ret << sentence
              else
                ret << (text + sentence)
              end
              return ret
            end
          end
        end
        text_length += downsize_unless_japanese(sentence.slice(0, index + 1))
        break if text_length > @tweet_limit
        text += sentence.slice!(0, index + 1)
      end
      ret << text
    end
  end

  # 最新TWEETがそのテーマの終わりならば、@sequence_of_remix分mecab_tweetし、復帰
  def next_sentence_id
    current_id =
      Theme.find_by_sql("SELECT current_sentence_id FROM themes WHERE current_sentence_id > 0").map(&:current_sentence_id)[0]
    if @sequence_of_remix == 0
      return current_id
    elsif @client.user_timeline(count: @sequence_of_remix).map{ |t| delete_https(t.text)[-1] =~ /#{@end_of_theme}|\!/ }.any?
      # mecab_tweet
      return
    else
      return current_id
    end
  end

  # 新しいテーマを決める
  def choose_next_theme(id, size)
    next_id = Theme.where(open: true).map(&:id).select{ |i| id < i }.min
    Theme.find_by("current_sentence_id > 0").update(current_sentence_id: nil)
    # データの更新
    func =
      -> theme_no { query = '【' + theme_no.to_s + '】' + '%'
        Text.find_by_sql("SELECT sentence_id FROM texts WHERE text LIKE '#{query}'").map(&:sentence_id)[0] }
    if next_id
      next_theme = Theme.find(next_id).theme_id
      Theme.find_by(id: next_id).update(current_sentence_id: func.call(next_theme))
      return '【' + next_theme.to_s + '】' + 'new!'
    else
      range = size / @inv_reuse_range
      # 新しいものが選択される確率が高くなるようにする
      next_theme = Theme.where(open: true).order("id").limit(range).map(&:theme_id).flat_map{ |t| t > 100 ? [t, t] : t }.sample

      # /themesのviewが最新順になるようにソートするため、一度削除する。
      Theme.find_by(theme_id: next_theme).destroy
      Theme.create({theme_id: next_theme, open: true, current_sentence_id: func.call(next_theme)})
      return
    end
  end

  def extra_tweet(tweet, medias, reply)
    if medias
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
       media_ids = (0...n).map{ |i| open("hoge_#{i}.png") }
    end
    if media_ids && reply
      @client.update_with_media(tweet, media_ids, { in_reply_to_status_id: reply })
    elsif media_ids
      @client.update_with_media(tweet, media_ids)
    elsif reply
      update(tweet, { in_reply_to_status_id: reply })
    end
  end

  # リンクは、文字数（23文字）に含まれる。(2016/9/20現在)。さらに半角とする(2017/11/08改定)
  def downsize_unless_japanese(sentence)
    half_char = delete_https(sentence).split('').map{ |c| c.match(/[ -~｡-ﾟ\n]/) }.compact.count
    katakana = delete_https(sentence).split('').map{ |c| c.match(/[ｧ-ﾝﾞﾟ]/) }.compact.count
    url_length = URI.extract(sentence).map{ |http| [http.length, @url_length].min }.reduce(:+) || 0
    delete_https(sentence).length - (half_char - katakana) + (url_length + half_char - katakana + 1) / 2
  end

  # (2016/9/20から)メディアツイートの文字数はカウントされない。
  def split_tweet(tweet)
    text = ''
    text_length = 0
    loop do
      index = tweet.index(/[。？\?！\!#{@end_of_theme}]/) || tweet.length - 1
      break if index == -1
      text_length += downsize_unless_japanese(tweet.slice(0, index + 1))
      break if text_length > @tweet_limit
      text += tweet.slice!(0, index + 1)
    end
    text.empty? ? [tweet, text] : [text, tweet]
  end

  def update(tweet, extra = nil)
    begin
      extra ? @client.update(tweet, extra) : @client.update(tweet)
    rescue => e
      STDERR.puts "[EXCEPTION] " + e.to_s
      exit 1
    end
  end

  # マルコフ連鎖用辞書の作成
  def make_dic(dic)
    nm = Natto::MeCab.new
    data = ['BEGIN','BEGIN']
    @texts.each do |t|
      nm.parse(t) do |a|
        data << a.surface if a.surface
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
      tweet1, tweet2 = tweets
      if tweet2
        tweet2 += @mention_tweet_remix + "\n" + @hash_tag_remix
        if tweet2.length <= @tweet_limit
          return [tweet1, tweet2]
        end
      else
        # @mention_tweet_remixと@hash_tag_remixは半角とする(2017/11/08改定)
        if tweet1.length <= @tweet_limit - (@mention_tweet_remix.length + 1 + @hash_tag_remix.length + 1) / 2
          return [tweet1 + @mention_tweet_remix + "\n" + @hash_tag_remix, tweet2]
        else
          return [tweet1, @mention_tweet_remix + "\n" + @hash_tag_remix]
        end
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
