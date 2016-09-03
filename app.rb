require 'rubygems'
require 'sinatra'
require 'sinatra/reloader'
require 'active_record'
require './models/sentence.rb'
require './tweet.rb'

enable :sessions

helpers do
  def login?
    if session[:username].nil?
      return false
    else
      return true
    end
  end
end


get '/' do
  if login?
    @title = '文章登録'
    @tweets = Text.order("id desc").all
    @texts = @tweets.last.text # ダミー
    erb :index
  else
    redirect '/login'
  end
end

post '/new' do
  @texts = Tweet.new.from_sentence_to_tweets(params[:sentence].dup)
  if @texts && @texts[0] != "\n"
    sentence = Sentence.create({sentence: params[:sentence]})
    @texts.each do |t|
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
    themes = Theme.where(open: true)
    if themes && !themes.find_by("current_sentence_id > 0")
      query = '【' + themes.first.theme_id.to_s + '】' + '%'
      id = Sentence.find_by_sql("SELECT id FROM texts WHERE text LIKE '#{query}'").map(&:id)[0]
      themes.first.update(current_sentence_id: id)
    end
    redirect '/'
  else
    @title = '文章登録'
    @tweets = Text.order("id desc").all
    erb :index
  end
end

post '/delete' do
  Sentence.find(params[:id]).destroy
end

get '/theme' do
  @title = 'テーマ番号登録'
  @themes = Theme.order("id desc").all
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

post '/media_delete' do
  MediaTweet.find(params[:id]).destroy
end

get '/login' do
  @title = 'ログイン'
  @user = User.new
  erb :login
end

post '/login' do
  @user = User.new(name: params[:name])
  @user.encrypt_password(params[:password])
  if @user.name == '' || !@user.salt
    erb :login
  elsif User.authenticate(params[:name], params[:password])
    session[:username] = params[:name]
    redirect '/'
  else
    erb :error
  end
end

get '/logout' do
  session[:username] = nil
  redirect '/'
end

get '/signup' do
  @title = '登録'
  @user = User.new
  erb :signup
end


post '/signup' do
  @title = '登録'
  if params[:password] != params[:password_confirmation]
    redirect '/error'
  end
  @user = User.new(name: params[:name])
  @user.encrypt_password(params[:password])
  if @user.save
    session[:username] = params[:name]
    redirect '/'
  else
    erb :signup
  end
end

get '/error' do
  @title = 'エラー'
  erb :error
end


get '/normal_tweet' do
  Tweet.new.normal_tweet
end

get '/mecab_tweet' do
  Tweet.new.random_tweet_using_mecab
end
