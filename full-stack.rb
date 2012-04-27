require 'ostruct'
application_name = `pwd`.split('/').last.strip
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
gem 'unicorn' if choices.heroku
if choices.active_admin
  gem 'meta_search', version: '>= 1.1.0.pre'
  gem 'activeadmin'
end

gem_group :development do
  gem 'sqlite3'
  gem 'smusher' if choices.assets
  gem 'heroku' if choices.heroku
  gem 'foreman' if choices.heroku
end

gem_group :development, :test do
  gem "minitest-rails", git: 'https://github.com/blowmage/minitest-rails.git'
  gem 'minitest-reporters'
  gem "spinach-rails", group: 'test'
  gem 'guard-spinach'
  gem 'guard-minitest'
end

gem_group :assets do
  gem 'sass-rails'
  gem 'compass-rails'
  gem 'uglifier'
end
gem 'jquery-rails'

gem_group :production do
  gem 'rack-cache'
  gem 'pg'
  gem 'fog' if choices.s3
end

run "bundle install"

# Add minitest
generate 'mini_test:install'
application <<-eos
config.generators do |g|
  g.test_framework :mini_test, spec: true
end
eos

# Fix the rake file
File.open('Rakefile', 'a') do |f|
  f.write <<-eos
require 'rake/testtask'
Rake::TestTask.new do |t|
  t.test_files = Dir.glob("test/**/*_test.rb")
end

task :default => [:test, :spinach]
  eos
end

File.open('test/minitest_helper.rb', 'a') do |f|
  f.puts "require 'minitest/reporters'"
  f.puts "MiniTest::Unit.runner = MiniTest::SuiteRunner.new"
  f.puts "MiniTest::Unit.runner.reporters << MiniTest::Reporters::SpecReporter.new"
end

File.open('Guardfile', 'w') do |f|
  f.write <<-eos
guard 'minitest' do
  watch(%r|^test/(.*)_test\.rb|)
  watch(%r|^test/minitest_helper\.rb|)    { "test" }
  watch(%r|^lib/(.*)([^/]+)\.rb|)     { |m| "test/lib/\#{m[1]}\#{m[2]}_test.rb" }
  watch(%r|^app/(.*)/(.*)\\.rb|) { |m| "test/\#{m[1]}/\#{m[2]}_test.rb" }
end
  eos
end

# Initialize spinach
generate 'spinach'

# Install devise
if choices.devise
  generate "devise:install"
  generate "devise", choices.devise_user_model
end

run "guard init spinach"

# Install active_admin
if choices.active_admin
  generate "active_admin:install", choices.active_admin_user_model
end

# If using heroku
if choices.heroku
  application 'config.assets.initialize_on_precompile = false'
  File.open('Procfile', 'w') do |f|
    f.write <<-eof
web: bundle exec unicorn_rails -p $PORT -c ./unicorn.rb
    eof
  end
  File.open('unicorn.rb', 'w') do |f|
    f.write <<-eof
worker_processes 3 # amount of unicorn workers to spin up
timeout 120         # restarts workers that hang for 30 seconds
    eof
  end
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

# Init compass stylesheets
run "bundle exe compass init rails --syntax sass"

# Init a proper application layout
run "rm app/views/layouts/application.html.erb"
File.open('app/views/layouts/application.html.slim', 'w') do |f|
  f.write <<-eos
doctype html
html
  head
    title #{application_name.camelize}
    = stylesheet_link_tag 'application', media: 'all'
    = javascript_include_tag 'application'
    = csrf_meta_tags
    /*link rel="shortcut icon" href=image_path('favicon.png')*/
  body
    =yield
  eos
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