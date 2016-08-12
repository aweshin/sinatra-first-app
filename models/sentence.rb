require 'active_record'
# データベースへの接続
ActiveRecord::Base.establish_connection(
  ENV['DATABASE_URL'] || 'sqlite3://localhost/sentence.db'
)


class Text < ActiveRecord::Base
end