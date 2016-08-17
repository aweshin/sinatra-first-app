require 'active_record'
# データベースへの接続
ActiveRecord::Base.configurations = YAML.load_file('db/database.yml')
ActiveRecord::Base.establish_connection(ENV['DATABASE_URL'] || :development)


class Sentence < ActiveRecord::Base
    has_many :texts, dependent: :destroy
    validates :sentence, presence: true
end

class Text < ActiveRecord::Base
  has_many :media_tweets
  belongs_to :theme
  belongs_to :sentence
end

class Theme < ActiveRecord::Base
  has_many :texts
  validates :theme_id, presence: true
end

class MediaTweet < ActiveRecord::Base
  belongs_to :text
  validates :with_media, presence: true
  validates :media, presence: true
end