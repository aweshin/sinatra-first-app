class CreateSentences < ActiveRecord::Migration
  def change
    create_table :text do |t|
      t.string :sentence
    end
  end
end
