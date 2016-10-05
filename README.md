## About This App

This is a Sinatra App for heroku deployment.  
Also this is a twitter_bot powered by heroku.(Twitter locale is only Japanese. sorry...)  
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
    $ heroku addons:add heroku-postgresql
    $ heroku pg:promote HEROKU_POSTGRESQL_(COLOR)_URL
    
And create an app and push the source.

    $ git push heroku master

Then, migrate with the database.

    $ heroku run bundle exec rake db:migrate
    
## Heroku settings

This app needs Mecab engine.

    $ heroku config:set \
        BUILDPACK_URL=https://github.com/diasks2/heroku-buildpack-mecab.git\
        LD_LIBRARY_PATH=/app/vendor/mecab/lib\
        MECAB_PATH=/app/vendor/mecab/lib/libmecab.so

You should set up following heroku config vars and add-ons.

    $ heroku config:set AWS_REGION=xxxxxxxx
    $ heroku config:set AWS_ACCESS_KEY_ID=xxxxxxxx
    $ heroku config:set AWS_SECRET_ACCESS_KEY=xxxxxxxx
    $ heroku config:set S3_BUCKET_NAME=xxxxxxxx
    $ heroku config:set TWITTER_ACCESS_TOKEN=xxxxxxxxx
    $ heroku config:set TWITTER_ACCESS_TOKEN_SECRET=xxxxxxxxx
    $ heroku config:set TWITTER_CONSUMER_KEY=xxxxxxxxx
    $ heroku config:set TWITTER_CONSUMER_SECRET=xxxxxxxxx
    $ heroku addons:add scheduler:standard

Please select "Add new job" on https://scheduler.heroku.com/dashboard to set up Heroku Scheduler.  
Then, fill in the "TASK" blank with "bundle exec ruby task.rb".  
You can choose "daily", "hourly" or "10 minutes" at the "Task frequency".

If you want to tweet with media(.png/.gif), please sign up aws (https://aws.amazon.com/jp/register-flow/) and then make a bucket(bucket name should be registered on your heroku configs.) and make a folder "/media" on the s3 service.