require 'ostruct'
application_name = `pwd`.split('/').last
run "echo > Gemfile"

choices = OpenStruct.new

choices.i18n = yes?("Will this application use I18n?")
choices.json = yes?("Will you output json?")
choices.heroku = yes?("Will you use heroku?")

if choices.devise = yes?("Will you use devise?")
  choices.devise_user_model = ask("What would you like the user model to be called? [User]")
  choices.devise_user_model = 'User' if choices.devise_user_model.blank?
end

if choices.active_admin = yes?("Will you use active_admin?")
  choices.active_admin_user_model = ask("What would you like the Admin user model to be called? [AdminUser]")
  choices.active_admin_user_model = 'AdminUser' if choices.active_admin_user_model.blank?
end

if choices.uploads = yes?("Will this app have file uploads?")
  choices.s3 = yes?("Will they be over S3?")
end
choices.assets = yes?("Do you want to optimize this app's assets for performance?")

add_source :rubygems
gem 'rails'
gem "slim-rails"
gem "simple_form"
gem 'draper'
gem 'button_form'
gem 'flash_messages_helper'
gem 'rails-i18n' if choices.i18n
gem 'jbuilder' if choices.json
gem 'carrierwave' if choices.uploads
gem 'devise' if choices.devise
if choices.active_admin
  gem 'meta_search', version: '>= 1.1.0.pre'
  gem 'activeadmin'
end

gem_group :development do
  gem 'sqlite3'
  gem 'smusher' if choices.assets
  gem 'heroku' if choices.heroku
end

gem_group :development, :test do
  gem "minitest-rails"
end

gem_group :test do
  gem "spinach-rails", group: 'test'
end

gem_group :assets do
  gem 'sass-rails'
  gem 'compass-rails'
end
gem 'jquery-rails'

gem_group :production do
  gem 'pg'
  gem 'fog' if choices.s3
end

run "bundle install"

# Install devise
if choices.devise
  generate "devise:install"
  generate "devise", choices.devise_user_model
end

# Install active_admin
if choices.active_admin
  generate "active_admin:install", choices.active_admin_user_model
end

# Use carrierwave with s3
if choices.s3
  initializer 'carrierwave.rb', <<-eos
CarrierWave.configure do |config|
  config.permissions = 0666
  if Rails.env.test?
    config.enable_processing = false
  end
  if Rails.env.production?
    config.storage = :fog
    config.fog_credentials = {
      provider: 'AWS',
      aws_access_key_id: ENV['S3_KEY'],
      aws_secret_access_key: ENV['S3_SECRET'],
      region: ENV['S3_REGION']
    }
    config.fog_directory = ENV['S3_BUCKET']
    config.fog_attributes = {'Cache-Control'=>'max-age=315576000'}
    config.fog_public     = true
  else
    config.storage = :file
  end
end
  eos
end

# Optimize asset performance
if choices.assets
  application 'config.serve_static_assets = true', env: :production
  application 'config.static_cache_control = "public, max-age=864000"', env: :production
  application "config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect'", env: :production
  application "config.middleware.use Rack::Cache, verbose: false", env: :production
  application "config.middleware.insert_before Rack::Cache, Rack::Deflater", env: :production
end

# Cleanup
run "rm app/assets/images/rails.png"
run "rm public/index.html"
run "rm public/favicon.ico"
run "rm README.rdoc"
File.open('Readme.md', 'w') do |file|
  file.write <<-eos
# {application_name}

Write something here
  eos
end

run 'rake db:migrate'

File.open('.gitignore', 'a') do |f|
  f.puts ".DS_Store"
  f.puts ".sassc"
end

File.open(".rvmrc", 'w') do |f|
  f.puts "rvm --create use 1.9.3@#{application_name}"
end

# set up git
git :init
git :add => '.'
git :commit => "-a -m 'Initial commit'"