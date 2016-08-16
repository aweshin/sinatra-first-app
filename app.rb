require 'rubygems'
require 'sinatra'
require 'sinatra/reloader'
require 'active_record'
require './models/sentence.rb'
require './models/theme.rb'
require './models/media_tweet.rb'
require './tweet.rb'

get '/' do
  @title = 'main index'
  @sentences = Sentence.order("id desc").all
  erb :index
end

post '/new' do
  sentence = Sentence.create({sentence: params[:sentence]})
  Tweet.new.create_texts(params[:sentence], sentence.id)
  redirect '/'
end

post '/delete' do
  Sentence.find(params[:id]).destroy
end

get '/theme' do
  @title = 'Themes'
  @themes = Theme.all
  erb :theme
end

post '/theme_new' do
  Theme.create({theme_id: params[:theme_id], open: params[:open] == 'on'})
  redirect '/'
end

get '/media' do
  @title = 'MediaTweet'
  erb :media
end

post '/media_new' do
  media = MediaTweet.create({with_media: params[:with_media], media: params[:media]})
  redirect '/'
end

get '/normal_tweet' do
  Tweet.new.normal_tweet
end
