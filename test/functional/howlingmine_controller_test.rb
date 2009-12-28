require File.dirname(__FILE__) + '/../test_helper'
require 'howling_mine_controller'
require 'test/unit'

class HowlingMineControllerTest < Test::Unit::TestCase
  
  def setup
    @controller = HowlingMineController.new
    @request    = ActionController::TestRequest.new
    @response   = ActionController::TestResponse.new
    @api_key = Setting.mail_handler_api_key
  end

 
  def test_issue_new
   #@request.session[:user_id] = 2
   # post :new, :project_id => 1, 
   #             :issue => {:tracker_id => 3,
   #                        :subject => 'This is the test_new issue',
   #                       :description => 'This is the description',
   #                        :priority_id => 5,
   #                        :estimated_hours => '',
   #                        :custom_field_values => {'2' => 'Value for field 2'}}
    #assert_redirected_to 'issues/show'
    
    #issue = Issue.find_by_subject('This is the test_new issue')
    #assert_not_nil issue
    #assert_equal 2, issue.author_id
    #assert_equal 3, issue.tracker_id
    #assert_nil issue.estimated_hours
    #v = issue.custom_values.find(:first, :conditions => {:custom_field_id => 2})
    #assert_not_nil v
    #assert_equal 'Value for field 2', v.value
  end
  
  def test_check_api_key
    get :plugin_version
    assert_response 403
    api_key = Setting.mail_handler_api_key
    get :plugin_version, :api_key => @api_key
    assert_response :success
  end
  
  def test_plugin_version
    get :plugin_version
    assert_response 403
    get :plugin_version, :api_key => @api_key
    assert_response :success
    assert_not_nil(@response.body =~ /^"\d.*/)
  end

  def test_new_issue
    #post :new_issue, :tracker
  end
  
  def test_issues
    get :issues
    assert_response 403
    get :issues, :api_key => @api_key
    assert_response :success
    assert_not_nil @response.body
    issues = JSON.parse(@response.body)
    assert !issues.nil?
  end
  
  def test_issue_status
    get :issue_status
    assert_response 403
    get :issue_status, :api_key => @api_key, :issue_id => 999999999
    assert_response 404
    get :issue_status, :api_key => @api_key
    assert_response 400
    
    get :issue_status, :api_key => @api_key, :issue_id => 1
    assert @response.body
    assert @response.body == 'New'
    
    get :issue_status, :api_key => @api_key, :issue_id => 'dd'
    assert_response 404
  end
  
  def test_journals
    get :journals
    assert_response 403
    get :journals, :api_key => @api_key, :issue_id => 999999999
    assert_response 404
    get :journals, :api_key => @api_key
    assert_response 400
    
    get :journals, :api_key => @api_key, :issue_id => 1
    assert @response.body
    assert_nothing_raised do
      journals = JSON.parse @response.body
      assert journals.is_a?(Array)
    end
    
    get :journals, :api_key => @api_key, :issue_id => 'dd'
    assert_response 404
  end
  
  def test_projects
    get :projects
    assert_response 403
    
    get :projects, :api_key => @api_key
    assert @response.body
    assert_nothing_raised do
      projects = JSON.parse @response.body
      assert projects.is_a?(Array)
    end
  end
  
  def test_count_issues
     get :count_issues
     assert_response 403
     get :count_issues, :api_key => @api_key
     assert_not_nil @response.body
     @response.body.is_a? Integer
  end
  
  def test_count_projects
    get :count_projects
    assert_response 403
    get :count_projects, :api_key => @api_key
    assert_not_nil @response.body
    @response.body.is_a? Integer
  end
  
  def test_find
    get :find
    assert_response 403
    get :find, :api_key => @api_key
    assert_not_nil @response.body
    issues = JSON.parse(@response.body)
    assert(issues.is_a?(Array))
    
    get :find, :api_key => @api_key, :method => 1
    assert_not_nil @response.body
    assert_nothing_raised do
      issue = JSON.parse(@response.body)
      assert_not_nil issue["subject"]
    end
    
    get :find, :api_key => @api_key, :method => 'all'
    assert_not_nil @response.body
    issues = JSON.parse(@response.body)
    assert(issues.is_a?(Array))
    
    get :find, :api_key => @api_key, :method => 999999
    assert_not_nil @response.body
    assert_response 404
  end
  
  def post_issue(subject, desc, custom_fields)
  end    
    
end
