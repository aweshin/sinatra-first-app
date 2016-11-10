require './app.rb'
require './signup.rb'

use ActiveRecord::ConnectionAdapters::ConnectionManagement

run Sinatra::Application
