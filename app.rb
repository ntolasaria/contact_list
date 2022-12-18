require "sinatra"
require "sinatra/reloader"
require "tilt/erubis"
require "yaml"
require "bcrypt"

configure do
  enable :sessions
  set :session_secret, "secret"
end

def logged_in?
  !!session[:username]
end

def require_login
  redirect "/" unless logged_in?
end

def data_path
  if ENV["RACK_ENV"] == "test"
    File.expand_path("../test/data", __FILE__)
  else
    File.expand_path("../data", __FILE__)
  end
end

def sorted_contacts
  sorted = session[:contacts].sort_by { |contact| contact[:name].downcase }
  sorted.each { |contact| yield contact }
end


def load_contacts
  path = File.join(data_path, "contacts/#{session[:username]}.yml")

  File.exist?(path) ? YAML.load_file(path) : []
end

def load_user_credentials
  path = File.join(data_path, "users.yml")
  File.exist?(path) ? YAML.load_file(path) : {}
end

def valid_user?(username, password)
  users = load_user_credentials
  if users.key?(username)
    bcrypt_password = BCrypt::Password.new(users[username])
    bcrypt_password == password
  else
    false
  end
end

def create_new_user(username, password)
  users = load_user_credentials
  return true if users.key?(username)

  bcrypt_password = BCrypt::Password.create(password).to_s
  users[username] = bcrypt_password

  File.write(File.join(data_path, "users.yml"), users.to_yaml)
  nil
end

def add_contacts_to_file
  path = File.join(data_path, "contacts/#{session[:username]}.yml")
  File.write(path, session[:contacts].to_yaml)
end

def generate_uid
  return 1 if session[:contacts].empty?
  session[:contacts].max_by { |contact| contact[:uid] }[:uid] + 1
end

def validate_details_return_error(name, phone)
  if !name.empty? && phone.match?(/\A\d{10}\z/)
    false
  else
    "Please enter a valid name and phone number"
  end
end

def create_contact(uid, name, phone, email=nil)
  hash = { uid: uid, name: name, phone: phone }
  hash[:email] = email if email
  hash
end

def matching_contacts(query)
  select_contacts do |uid, *details|
    details.any? { |detail| detail.downcase.include?(query) }
  end
end

def select_contacts
  matching = []
  session[:contacts].each do |contact|
    matched = yield contact.values
    matching << contact if matched
  end
  matching
end

def find_contact(uid)
  session[:contacts].find { |contact| contact[:uid] == uid }
end

before do
  @contacts = session[:contacts]
end

get "/" do
  erb :home
end

get "/login" do
  erb :login
end

post "/login" do
  username = params[:username]
  password = params[:password]

  if valid_user?(username, password)
    session[:username] = username
    session[:contacts] = load_contacts
    redirect "/"
  else
    status 422
    session[:error] = "Please enter valid username and password!"
    erb :login
  end
end

get "/signup" do
  erb :signup
end

post "/signup" do
  username = params[:username].strip
  password = params[:password].strip

  if username.size == 0 || password.size == 0
    status 422
    session[:error] = "Username and password must have a valid character!"
    erb :signup
  else
    error = create_new_user(username, password)
    if error
      status 422
      session[:error] = "Username exists! please select another username"
      erb :signup
    else
      session[:message] = "New user, #{username} has been created, please sign in to continue"
      redirect "/"
    end
  end
end

get "/add" do
  require_login

  erb :add
end

post "/add" do
  require_login

  name = params[:name].strip
  phone = params[:phone].strip
  email = params[:email].strip
  email = nil if email.empty?
  uid = generate_uid

  error = validate_details_return_error(name, phone)

  if error
    status 422
    session[:error] = error
    erb :add
  else
    contact = create_contact(uid, name, phone, email)
    session[:contacts] << contact
    session[:message] = "New contact, #{name} has been added"
    redirect "/"
  end
end

get "/all" do
  require_login

  erb :all
end

get "/contact/:uid" do
  require_login

  uid = params[:uid].to_i
  @contact = find_contact(uid)
  erb :contact
end

post "/contact/:uid/update" do
  require_login

  uid = params[:uid].to_i
  @contact = find_contact(uid)
  name = @contact[:name]
  choice = params[:choice]

  case choice
  when "delete"
    session[:contacts].delete_if { |contact| contact[:uid] == uid }
    session[:message] = "The contact, #{name} has been deleted"
    redirect "/all"
  when "edit"
    erb :contact_edit
  end
end

post "/contact/:uid/edit" do
  require_login

  uid = params[:uid].to_i
  @contact = find_contact(uid)
  name = params[:name]
  phone = params[:phone]
  email = params[:email]

  error = validate_details_return_error(name, phone)
  if error
    status 422
    session[:error] = error
    erb  :contact_edit
  else
    @contact[:name] = name
    @contact[:phone] = phone
    @contact[:email] = email
    session[:message] = "Contact successfully edited"
    redirect "/contact/#{uid}"
  end
end

get "/savetofile" do
  require_login

  add_contacts_to_file
  session[:message] = "All contacts have been saved"
  redirect "/"
end

get "/search" do
  require_login

  query = params[:query].strip.downcase

  if query.size < 3
    status 422
    session[:error] = "The search query must be atleast 3 characters long"
    erb :all
  else
    @matching_contacts = matching_contacts(query)
    erb :search
  end
end

get "/logout" do
  add_contacts_to_file
  session.clear

  redirect "/"
end
