class ModifyTexts < ActiveRecord::Migration
  def down
    remove_column :texts, :words
  end
end
