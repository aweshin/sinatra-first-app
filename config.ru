require_relative  'app.rb'

use ActiveRecord::ConnectionAdapters::ConnectionManagement

run Sinatra::Application
