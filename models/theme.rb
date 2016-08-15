require 'active_record'
# データベースへの接続
ActiveRecord::Base.configurations = YAML.load_file('db/database.yml')
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'] || :development)

class Theme < ActiveRecord::Base
  has_many :texts
end
