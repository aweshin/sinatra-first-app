class CreateTexts < ActiveRecord::Migration
  def change
    create_table :texts do |t|
      t.string :text
      t.boolean :media, default: false  # メディアツイートフラグ
      t.integer :sentence_id
    end
  end
end
