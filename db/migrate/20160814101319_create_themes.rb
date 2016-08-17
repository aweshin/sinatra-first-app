class CreateThemes < ActiveRecord::Migration
  def change
    create_table :themes do |t|
      t.integer :theme_id
      t.boolean :open, default: true  # 公開するか?
      t.integer :current_text_id
    end
  end
end
