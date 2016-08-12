require './models/sentence.rb'

Sentence.order("id desc").all.each_with_index do |text, index|
  Sentence.create(id: index + 1, sentence: text)
end
