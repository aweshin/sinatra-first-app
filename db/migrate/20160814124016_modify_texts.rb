class ModifyTexts < ActiveRecord::Migration
  def down
    add_column :texts, :sentence_id, :integer
  end
end
