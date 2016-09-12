require 'active_record'
require 'bcrypt'
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

class User < ActiveRecord::Base
  validates :name, presence: { message: "入力してください。" }
  validates :salt, presence: { message: "入力してください。" }
  validates :passwordhash, confirmation: true

  def self.authenticate(name, password)
    user = self.where(name: name).first
    if user && user.passwordhash == BCrypt::Engine.hash_secret(password, user.salt)
      user
    else
      nil
    end
  end

  def encrypt_password(password)
    if password.present?
      self.salt = BCrypt::Engine.generate_salt
      self.passwordhash = BCrypt::Engine.hash_secret(password, salt)
    end
  end
end