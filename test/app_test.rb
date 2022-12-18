ENV["RACK_ENV"] = "test"

require "minitest/autorun"
require "rack/test"
require "fileutils"

require_relative "../app"

class ContactListTest < Minitest::Test
  include Rack::Test::Methods
  
  def app
    Sinatra::Application
  end

  def setup
    FileUtils.mkdir_p(data_path)
    FileUtils.mkdir_p(File.join(data_path, "contacts"))
  end

  def teardown
    FileUtils.rm_rf(data_path)
    FileUtils.rm_rf(File.join(data_path, "contacts"))
  end

  def initialize_admin_in_file
    user = { "admin" => "$2a$12$DPLsniY4MWFXqDx2Np1K4ee7CE5eJCSkjcvpgQKUHgZwpk9cXxF/6" }
    File.write(File.join(data_path, "users.yml"), user.to_yaml)
  end

  def admin_session
    { "rack.session" => { username: "admin", contacts: [{ uid: 1, name: "test", phone: "9830098300" }] } }
  end

  def session
    last_request.env["rack.session"]
  end

  # def add_test_contact
  #   session[:contacts] = [{ uid: 1000, name: "test", phone: "9830098300" }]
  # end

  def test_index
    get "/"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<a href="/login">)
  end

  def test_login_page
    get "/login"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit">Log In)
  end

  def test_login_with_valid_credentials
    initialize_admin_in_file
    post "/login", username: "admin", password: "secret"

    assert_equal 302, last_response.status
    assert_equal "admin", session[:username]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Logged in as admin"
  end

  def test_login_with_invalid_credentials
    post "/login", username: "admin", password: "admin"

    assert_equal 422, last_response.status
    assert_nil session[:username]
    assert_includes last_response.body, "Please enter valid username and password" 
  end

  def test_signup_form
    get "/signup"

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit">Sign Up)
  end

  def test_signup_with_valid_credentials
    post "/signup", username: "test", password: "password"

    assert_equal 302, last_response.status
    assert_equal "New user, test has been created, please sign in to continue", session[:message]
  end

  def test_signup_with_invalid_credentials
    post "/signup", username: "test", password: "   "

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Username and password must have a valid character!" 
  end

  def test_signup_with_existing_username
    initialize_admin_in_file

    post "/signup", username: "admin", password: "test"

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Username exists! please select another username"
  end

  def test_add_contact_form
    initialize_admin_in_file

    get "/add", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<button type="submit">Add)
  end

  def test_add_valid_contact
    initialize_admin_in_file

    post "/add", { name: "test", phone: "9830098300", email: "" }, admin_session

    assert_equal 302, last_response.status
    assert_equal "test", session[:contacts].last[:name]
    assert_equal 2, session[:contacts].last[:uid]
    assert_equal "New contact, test has been added", session[:message]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "New contact, test has been added"
  end

  def test_add_invalid_contact
    initialize_admin_in_file

    post "/add", { name: "test", phone: "9830", email: "" }, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "Please enter a valid name and phone number"
  end

  def test_all_contacts_page
    initialize_admin_in_file

    get "/all", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, %q(<h4>All Contacts:</h4>)
    assert_includes last_response.body, %q(<li><a href="/contact/1">test)
  end

  def test_individual_contact_page
    initialize_admin_in_file

    get "/contact/1", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Name: test"
    assert_includes last_response.body, %q(value="edit">Edit</button>)
  end

  def test_editing_deleting_contact
    initialize_admin_in_file

    post "/contact/1/update", { choice: "delete" }, admin_session

    assert_equal 302, last_response.status
    assert_equal "The contact, test has been deleted", session[:message]
    assert_empty session[:contacts]

    get last_response["Location"]
    
    assert_equal 200, last_response.status
    refute_includes last_response.body, "Name: test"
  end

  def test_editing_contact_valid_details
    initialize_admin_in_file

    post "/contact/1/edit", { name: "test-edited", phone: "9830098300" }, admin_session

    assert_equal 302, last_response.status
    assert_equal "Contact successfully edited", session[:message]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Name: test-edited"
  end

  def test_editing_contact_invalid_details
    initialize_admin_in_file

    post "/contact/1/edit", { name: "test-edited", phone: "9830" }, admin_session

    assert_equal 422, last_response.status
    assert_nil session[:message]
    assert_includes last_response.body, "Please enter a valid name and phone number"
  end

  def test_savetofile
    initialize_admin_in_file

    get "/savetofile", {}, admin_session

    path = File.join(data_path, "contacts/admin.yml")
    file = YAML.load_file(path)
    contact = file.first

    assert_equal 302, last_response.status
    assert_equal "All contacts have been saved", session[:message]

    assert_equal "test", contact[:name]
    assert_equal 1, contact[:uid]
    assert_equal "9830098300", contact[:phone]

    get last_response["Location"]

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Logged in as admin"
  end

  def test_search_contact_valid_matching_query
    initialize_admin_in_file

    get "/search?query=test", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "Showing search results for '<em>test</em>'"
    assert_includes last_response.body, %q(<a href="/contact/1">test</a>)
  end

  def test_search_contact_valid_not_matching_query
    initialize_admin_in_file

    get "/search?query=admin", {}, admin_session

    assert_equal 200, last_response.status
    assert_includes last_response.body, "No results found.."
  end

  def test_search_contact_invalid_query
    initialize_admin_in_file

    get "/search?query=te", {}, admin_session

    assert_equal 422, last_response.status
    assert_includes last_response.body, "The search query must be atleast 3 characters"
  end

end