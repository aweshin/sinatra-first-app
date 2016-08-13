require 'active_record'
# データベースへの接続
ActiveRecord::Base.configurations = YAML.load_file('db/database.yml')
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'] || :development)


class Sentence < ActiveRecord::Base
end