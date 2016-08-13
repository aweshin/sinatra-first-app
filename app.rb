require 'rubygems'
require 'sinatra'
require 'sinatra/reloader'
require 'active_record'
require './models/sentence.rb'
require_relative 'tweet.rb'

get '/' do
  @sentences = Sentence.order("id desc").all
  erb :index
end

post '/new' do
  Sentence.create({sentence: params[:sentence]})
  redirect '/'
end

post '/delete' do
  Sentence.find(params[:id]).destroy
end

get '/normal_tweet' do
  Tweet.new.normal_tweet
end
