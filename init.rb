# 要修正
# Sentence追加分のみText.create/update_attribute したい
# app.rbに更新情報を移動

require './models/sentence.rb'
require './models/theme.rb'
require './models/media_tweet.rb'
require './models/text.rb'
require './tweet.rb'

tweet = Tweet.new
medias = MediaTweet.all
sentences = Sentence.all

index = []
sentences.each_with_index do |s, i|
  index << i if s.sentence.slice(0, 6).match(/【(\d+)】/)
end
index << sentences.size

media_texts = medias.map(&:with_media)
theme_numbers = Theme.where(open: true).map(&:theme_id)
index.each_cons(2).with_index do |(s, t), i|
  if theme_numbers.include?(i + 1)
    pick_up = sentences[s...t].map(&:sentence)
    text = tweet.join_text(pick_up.flat_map{ |t| tweet.from_text_to_tweets(t) })
    text.each do |t|
      media_inclusion = media_texts.map{ |mt| t.include?(mt) }
      Text.create({text: t, media: media_inclusion.any?})
      media_inclusion.each_with_index{ |m, i| MediaTweet.where(with_media: media_texts[i]).update_all(text_id: Text.find_by(text: t).id) if m }
    end
  end
end

