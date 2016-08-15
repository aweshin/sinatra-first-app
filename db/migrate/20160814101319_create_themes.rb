class CreateThemes < ActiveRecord::Migration
  def change
    create_table :themes do |t|
      t.integer :theme_id
      t.boolean :open, default: true  # 公開するか?
    end
  end
end
