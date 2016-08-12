require 'active_record'
# データベースへの接続
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'])


class Sentence < ActiveRecord::Base
end