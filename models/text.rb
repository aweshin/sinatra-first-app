require 'active_record'
# データベースへの接続
ActiveRecord::Base.configurations = YAML.load_file('db/database.yml')
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'] || :development)

class Text < ActiveRecord::Base
  has_many :media_tweets
  belongs_to :theme
  belongs_to :sentence
end
