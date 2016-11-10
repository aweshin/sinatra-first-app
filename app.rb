require 'rubygems'
require 'sinatra'
require 'sinatra/reloader'
require 'active_record'
require './models/sentence.rb'
require './tweet.rb'
require 'json'

enable :sessions

helpers do
  def login?
    if session[:username].nil?
      return false
    else
      return true
    end
  end

  def h(text)
    Rack::Utils.escape_html(text)
  end
end


get '/' do
  if login?
    @title = 'Twitter bot'
    erb :index
  else
    redirect '/login'
  end
end

get '/normal' do
  @title = '通常ツイート'
  @texts = '' # ダミー
  @tweets = Text.order("id desc").all
  @theme_no = session[:theme_id]
  session[:theme_id] = nil
  @done = session[:done]
  session[:done] = false
  @end_of_theme = Tweet.new.end_of_theme
  erb :normal
end

get '/shuffle' do
  @title = 'REMIX'
  @done = session[:done]
  session[:done] = false
  erb :shuffle
end

post '/new' do
  st = params[:sentence]
  @texts = Tweet.new.from_sentence_to_tweets(st.dup)
  if @texts && @texts[0] != "\n"
    sentence = Sentence.create({sentence: st})
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
    # theme_id登録（していなかったとき）
    if (md = st[0,6].match(/【(\d+)】/)) && !Theme.find_by(theme_id: md[1].to_i)
      Theme.create({ theme_id: md[1].to_i, open: true })
    end
    # themesテーブルの初期化
    themes = Theme.where(open: true)
    if themes && !themes.find_by("current_sentence_id > 0")
      query = '【' + themes.first.theme_id.to_s + '】' + '%'
      id = Sentence.find_by_sql("SELECT id FROM texts WHERE text LIKE '#{query}'").map(&:id)[0]
      themes.first.update(current_sentence_id: id)
    end
    session[:done] = true
    redirect '/normal'
  else
    redirect '/error'
  end
end

post '/shuffle_new' do
  user = params[:user]
  count = params[:count].to_i
  config = open('./config/config_remix_ver_on_db.json') do |io|
    JSON.load(io)
  end
  if user && 0 < count && count <= 2000
    delete_with = Regexp.new(config["特定の記号にくっついた文字列、または２つの記号に囲まれている文字を削除"]
                             .map{ |s| s.length == 1 ? Regexp.escape(s) + '.+' : Regexp.escape(s[0]) + '.+?' + Regexp.escape(s[1]) }.join('|'))
    delete_alone = Regexp.new(config["記号を削除"].map{ |s| s.length == 1 ? Regexp.escape(s) : '[' + s + ']' }.join('|'))
    put_end = Regexp.new(config["句点を追加"].map{ |s| Regexp.escape(s) }
                         .map{ |strs| strs[0, strs.length/2] + '(.+?)[？\?！\!]?' + strs[strs.length/2..-1] }.join('|'))
    timeline = Tweet.new.client.user_timeline("@" + user, { count: count })
    maxid = 0
    ((count - 1)/ 200 + 1).times do |i|
      timeline.map{ |t| t.text }.each do |t|
        next if config["登録NGワード"].map{ |ng| t.include?(ng) }.any?
        shuffles = Shuffle.all.map(&:sentence)
        nt = t.gsub(/#{HTTPS}/, '').gsub(delete_with, '').gsub(delete_alone, '').gsub(put_end, '\1'+'。')
        nt += '。' unless nt[-1] =~ /[。？\?！\!]/
        Shuffle.create({sentence: nt}) unless shuffles.include?(nt)
      end
      maxid = timeline[-1].id - 1
      timeline = Tweet.new.client.user_timeline("@" + user, { count: (i == count / 200 ? count % 200 : 200), max_id: maxid })
    end
    session[:done] = true
    redirect '/shuffle'
  else
    redirect '/error'
  end
end

post '/delete' do
  st = Sentence.find(params[:id])
  if md = st.sentence[0,6].match(/【(\d+)】/)
    Theme.find_by(theme_id: md[1].to_i).destroy
  end
  st.destroy
  redirect '/normal'
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
    session[:theme_id] = params[:theme_id]
  else
    target_theme.update(open: params[:open] == 'on')
  end
  redirect '/normal'
end

get '/media' do
  @title = 'メディアツイート登録'
  @medias = MediaTweet.all
  erb :media
end

post '/media_new' do
  phrase = params[:with_media]
  id = Text.find_by_sql("SELECT * FROM texts WHERE text LIKE '%#{phrase}%'").map(&:id)[0]
  redirect '/error' unless id
  media = MediaTweet.create({with_media: phrase, media: params[:media], tweet_id: id})
  Text.find(id).update(media: true)

  redirect '/error' if media.errors.any?
  redirect '/media'
end

post '/media_delete' do
  mt = MediaTweet.find(params[:id])
  t = Text.find_by(id: mt.tweet_id)
  t.update(media: false) if t
  mt.destroy
  redirect '/media'
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
    redirect '/error'
  end
end

get '/logout' do
  session[:username] = nil
  redirect '/'
end

get '/config' do
  json_file_path = './config/config_tweet.json'

  @json_data = open(json_file_path) do |io|
    JSON.load(io)
  end

  @inv_range_max = Theme.where(open: true).count
  erb :config
end

post '/config_new' do
  json_file_path = './config/config_tweet.json'

  json_data = open(json_file_path) do |io|
    JSON.load(io)
  end

  json_data.each do |data|
    json_data[data.to_a[0]] = params[data.to_a[0]] unless params[data.to_a[0]].empty?
  end

  open(json_file_path, 'w') do |io|
    JSON.dump(json_data, io)
  end
  redirect '/'
end

get '/config_db' do
  json_file_path = './config/config_remix_ver_on_db.json'

  @json_data = open(json_file_path) do |io|
    JSON.load(io)
  end
  erb :config_db
end

post '/config_db_new' do
  json_file_path = './config/config_remix_ver_on_db.json'

  json_data = open(json_file_path) do |io|
    JSON.load(io)
  end

  json_data.each_with_index do |data, i|
    strs = data.to_a[1].dup
    strs.each do |item|
      # update
      after = params[data.to_a[0]][item]
      if params["update"] && !after.empty?
        json_data[data.to_a[0]].delete(item)
        json_data[data.to_a[0]] << after
      end
    end
    # delete
    check = params[i.to_s]
    if check && params["delete"]
      check.each do |str, on|
        json_data[data.to_a[0]].delete(str)
      end
    end
    # insert
    add = params["new" + i.to_s]
    if add && params["update"]
      add.each do |str|
        json_data[data.to_a[0]] << str unless str.empty?
      end
    end
  end

  open(json_file_path, 'w') do |io|
    JSON.dump(json_data, io)
  end
  redirect '/'
end

get '/error' do
  @title = 'エラー'
  erb :error
end

get '/normal_tweet' do
  Tweet.new.normal_tweet
end

get '/random_tweet' do
  Tweet.new.random_tweet_remix
end
