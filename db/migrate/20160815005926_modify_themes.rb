class ModifyThemes < ActiveRecord::Migration
  def up
    rename_column :themes, :current_text, :current_text_id
  end
end
