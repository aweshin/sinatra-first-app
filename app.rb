require 'rubygems'
require 'sinatra'
require 'sinatra/reloader'
require 'active_record'
require './models/sentence.rb'
require './tweet.rb'

get '/' do
  @title = 'main index'
  @sentences = Sentence.order("id desc").all
  erb :index
end

post '/new' do
  sentence = Sentence.create({sentence: params[:sentence]})
  unless sentence.errors.any?
    tweet = Tweet.new
    text = tweet.from_sentence_to_tweets(params[:sentence].dup)
    text.each do |t|
      flag = false
      target_medias = []
      MediaTweet.all.each do |m|
        if t.include?(m.with_media)
          target_medias << m
          flag = true
        end
      end
      text = Text.create({text: t, media: flag, sentence_id: sentence.id})
      target_medias.map{ |m| m.update(tweet_id: text.id)}
    end
    # themesテーブルの初期化
    unless Theme.find_by("current_text_id > 0")
      new_theme = Theme.where(open: true).order(:theme_id).first
      new_id = Text.order(:id).first.id
      new_theme.update(current_text_id: new_id)
    end
    redirect '/'
  else
    redirect '/error'
  end
end

post '/delete' do
  Sentence.find(params[:id]).destroy
end

get '/theme' do
  @title = 'テーマ番号登録'
  @themes = Theme.all
  @new_theme_id = (theme = Theme.order("theme_id desc").first) ? theme.theme_id + 1 : 1
  erb :theme
end

post '/theme_new' do
  target_theme = Theme.find_by(theme_id: params[:theme_id])
  unless target_theme
    theme = Theme.create({theme_id: params[:theme_id], open: params[:open] == 'on'})
    redirect '/error' if theme.errors.any?
  else
    target_theme.update(open: params[:open] == 'on')
  end
  redirect '/'
end

get '/media' do
  @title = 'メディアツイート登録'
  @medias = MediaTweet.all
  erb :media
end

post '/media_new' do
  media = MediaTweet.create({with_media: params[:with_media], media: params[:media]})
  redirect '/error' if media.errors.any?
  redirect '/'
end

get '/error' do
  @title = 'エラー'
  erb :error
end

get '/normal_tweet' do
  Tweet.new.normal_tweet
end
