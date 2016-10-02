class CreateShuffles < ActiveRecord::Migration
  def change
    create_table :ohno_hijikata do |t|
      t.string :sentence
    end
  end
end
