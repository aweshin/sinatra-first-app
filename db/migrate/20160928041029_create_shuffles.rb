class CreateShuffles < ActiveRecord::Migration
  def change
    create_table :shuffles do |t|
      t.string :sentence
    end
  end
end
