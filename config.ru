require_relative  'app.rb'
require './app'

use ActiveRecord::ConnectionAdapters::ConnectionManagement

run Sinatra::Application
