class CreateMedias < ActiveRecord::Migration
  def change
    create_table :media_tweets do |t|
      t.integer :tweet_id
      t.string :with_media
      t.string :media
    end
  end
end
