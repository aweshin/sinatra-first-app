## About This App

This is a Sinatra App for heroku deployment.  
Also this is a twitter_bot powered by heroku.  
This App uses Twitter REST API with database (Active Record).  
  - Production: PostgreSQL
  - Development: SQLite3  

## How to Use  
Please clone this repository.  

    $ git clone https://github.com/aweshin/sinatra-first-app.git  
    $ cd sinatra-first-app

## With Database  

To use database, first add heroku-postgresql creating heroku app.(To use heroku command, heroku tool-belt should be installed in your computer.)

    $ heroku create
    $ heroku addons:create heroku-postgresql
    
And create an app and push the source.

    $ git push heroku master

Then, migrate with the database.

    $ heroku run bundle exec rake db:migrate
  
I think creating csv data is a better way if you want to insert the data into the heroku-postgresql.  
Then, use the following command.

    $ heroku pg:psql
    => \copy texts from 'texts.csv' CSV;
