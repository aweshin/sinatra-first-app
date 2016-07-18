require 'rubygems'
require 'sinatra'
require 'sinatra/reloader'
require_relative 'tweet.rb'
get '/' do
  'under construction'
end

get '/normal_tweet' do
  Tweet.new.normal_tweet
end

# get '/random_tweet_using_mecab' do
#   Tweet.new.random_tweet_using_mecab
# end
