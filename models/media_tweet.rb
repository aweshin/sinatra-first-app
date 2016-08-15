require 'active_record'
# データベースへの接続
ActiveRecord::Base.configurations = YAML.load_file('db/database.yml')
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'] || :development)

class MediaTweet < ActiveRecord::Base
  belongs_to :text
end
