class CreateTexts < ActiveRecord::Migration
  def change
    create_table :texts do |t|
      t.string :text
      t.boolean :media, default: false  # メディアツイートフラグ
    end
  end
end
