require 'rubygems'
require 'sinatra'
require 'sinatra/reloader'
require 'active_record'
require './models/sentence.rb'
require './tweet.rb'
require 'bcrypt'

enable :sessions

helpers do
  def login?
    if session[:username].nil?
      return false
    else
      return true
    end
  end

  def username
    return session[:username]
  end
end


get '/' do
  if login?
    @title = '文章登録'
    @sentences = Sentence.order("id desc").all
    erb :index
  else
    erb :login
  end
end

post '/new' do
  sentence = Sentence.create({sentence: params[:sentence]})
  redirect '/error' if sentence.errors.any?
  tweet = Tweet.new
  texts = tweet.from_sentence_to_tweets(params[:sentence].dup)
  texts.each do |t|
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

post '/login' do
  if user = User.find_by(name: params[:name])
    if user[:passwordhash] == BCrypt::Engine.hash_secret(params[:password], user[:salt])
      session[:username] = params[:name]
      redirect '/'
    end
  end
  erb :error
end

get '/logout' do
  session[:username] = nil
  redirect '/'
end

get '/signup' do
  erb :signup
end

post '/signup' do
  password_salt = BCrypt::Engine.generate_salt
  password_hash = BCrypt::Engine.hash_secret(params[:password], password_salt)

  User.create({name: params[:name], salt: password_salt, passwordhash: password_hash})
  session[:username] = params[:name]
  redirect '/'
end

get '/error' do
  @title = 'エラー'
  erb :error
end

get '/normal_tweet' do
  Tweet.new.normal_tweet
end
