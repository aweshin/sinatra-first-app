require_relative  'app.rb'
require 'active_record'

use ActiveRecord::ConnectionAdapters::ConnectionManagement

run Sinatra::Application
