class CreateMedias < ActiveRecord::Migration
  def change
    create_table :media_tweets do |t|
      t.string :with_media
      t.string :media
      t.integer :tweet_id
    end
  end
end
