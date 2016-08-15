class ModifyMedias < ActiveRecord::Migration
  def up
    remove_column :media_tweets, :target_text_id
  end
  def down
    add_column :media_tweets, :target_text_id, :integer
  end
end
