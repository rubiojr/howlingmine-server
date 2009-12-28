class HowlingMineController < ApplicationController
  require 'json'

  before_filter :check_if_login_required, :except => [:journals, :new_issue, :issue_status, :projects, :issues]
  skip_before_filter :verify_authenticity_token 
  before_filter :check_api_key
  unloadable  

  def journals
    id = params[:issue_id]
    if id
      issue = Issue.find(id.to_i)
      if issue
        render :status => 200, :text => issue.journals.to_json
      else
        render :status => 404, :text => 'Issue not found'
      end
    else
      logger.debug "HOWLING_MINE: issue_id not found in params," +
                    "returning all Journals"
      render :status => 200, :text => Journal.find(:all).to_json
    end
  end

  def issue_status
    id = params[:issue_id]
    if id
       issue = Issue.find(id.to_i)
      if issue
        render :status => 200, :text => issue.status.name
      else
        render :status => 404, :text => 'Issue not found'
      end
    else
      logger.debug "HOWLING_MINE: issue_id not found," +
                   "returning all the issue status"
      render :status => 200, :text => IssueStatus.find(:all).to_json
    end
  end
  
  def plugin_version
    render :status => 200, :text => (Redmine::Plugin.find :howlingmine_server).version.to_json
  end

  def projects
    render :status => 200, :text => Project.find(:all).to_json
  end

  def count_issues
    render :status => 200, :text => Issue.count.to_json
  end
  
  def count_projects
    render :status => 200, :text => Project.count.to_json
  end
  
  def find
    method = (params[:method] || 'all')
    logger.info "HOWLING_MINE: find method, #{params.inspect}"
    m = Integer(method) rescue method.to_sym
    if m.is_a? Integer
      logger.info "HOWLING_MINE: finding by record ID #{m}"
      issue = Issue.find(m)
      if not issue
        render :status => 404, :text => 'Issue not found'
        logger.info "HOWLING_MINE: issue #{m} not found"
      else
        inject_custom_fields(issue).to_json
        render :status => 200, :text => inject_custom_fields(issue).to_json
      end
    else
      p = {}
      offset = params[:offset]
      if offset
        p[:offset] = offset
      end

      limit = params[:limit]
      if limit
        p[:limit] = limit
      end

      issues = Issue.find(m, p)
      issues = inject_custom_fields(issues)
      render :status => 200, :text => issues.to_json
    end
  end
  
  def issues 
    issues = (Issue.find :all).map { |i| 
      cfields = {}
      i.available_custom_fields.each do |cf|
        cfields[cf.name] = i.custom_value_for cf.id
      end
      ihash = JSON.parse(i.to_json)
      ihash[:custom_fields] = cfields
      ihash 
    }      
    render :status => 200, :text => issues.to_json
  end

  def new_issue    
    find_or_create_custom_fields
    redmine_params = params
    logger.debug "HOWLING_MINE: New issue params #{params.inspect}"
    custom_fields = YAML.load(redmine_params[:custom_fields]) rescue nil

    if not custom_fields.is_a?(Hash)
      logger.error "HOWLING_MINE: issue custom fields not valid"
      custom_fields = {}
    end
    # redmine objects
    if params[:project].nil? or params[:tracker].nil?
      logger.error "HOWLING_MINE: project or tracker params nil"
      render :status => 400, :text => 'Invalid project/tracker params'
      return
    end
    project = Project.find_by_identifier(redmine_params[:project])
    if project.nil?
      logger.error "HOWLING_MINE: project #{params[:project]} not found"
      render :status => 400, :text => "Project #{params[:project]} not found"
      return
    end
    tracker = project.trackers.find_by_name(redmine_params[:tracker])
    if tracker.nil?
      logger.error "HOWLING_MINE: tracker #{params[:tracker]} not found"
      render :status => 400, :text => "Tracker #{params[:tracker]} not found"
      return
    end
    author = User.find_by_login(redmine_params[:author]) || User.anonymous

    subject = redmine_params[:subject] || 'no subject'
    description = redmine_params[:description] || 'no description'
    
    issue = Issue.find_or_initialize_by_subject_and_project_id_and_tracker_id_and_author_id(
      subject,
      project.id,
      tracker.id,
      author.id
    )
                                                                                                            
    if issue.new_record?
      # set standard redmine issue fields
      issue.category = IssueCategory.find_by_name(redmine_params[:category]) unless redmine_params[:category].blank?
      issue.assigned_to = User.find_by_login(redmine_params[:assigned_to]) unless redmine_params[:assigned_to].blank?
      issue.priority_id = redmine_params[:priority] unless redmine_params[:priority].blank?
      issue.description = description
    end

    issue.save!

    custom_fields.each do |k,v|
      f = IssueCustomField.find_or_initialize_by_name(k.to_s)
      project.issue_custom_fields << f unless project.issue_custom_fields.include?(f)
      tracker.custom_fields << f unless tracker.custom_fields.include?(f)
      cf = issue.custom_value_for(f) || issue.custom_values.build(:custom_field => f, :value => 0)
      cf.value = v
      cf.save!
    end
    
    # update journal
    journal = issue.init_journal(
      author, redmine_params[:description]
    )

    # reopen issue
    #if issue.status.blank? or issue.status.is_closed?                                                                                                        
    #  issue.status = IssueStatus.find(:first, :conditions => {:is_default => true}, :order => 'position ASC')
    #end

    issue.save!

    if issue.new_record?
      Mailer.deliver_issue_add(issue) if Setting.notified_events.include?('issue_added')
    else
      Mailer.deliver_issue_edit(journal) if Setting.notified_events.include?('issue_updated')
    end
    
    render :status => 200, :text => "#{issue.id}"
  end
  
  protected
  def find_or_create_custom_fields
    begin
      redmine_params = params
      custom_fields = YAML.load(redmine_params[:custom_fields])

      custom_fields.each do |key,val|
        f = IssueCustomField.find_or_initialize_by_name(key.to_s)
        if f.new_record?
          logger.info "HOWLING_MINE: Creating custom field #{key}"
          f.attributes = {:field_format => 'string', :searchable => true}
          if f.save(false)
            logger.info "HOWLING_MINE: custom field #{key} created!"
          else
            logger.error "HOWLING_MINE: Error creating custom field #{key}"
          end
        end

      end
    rescue Exception => e
      logger.error "HOWLING_MINE: Could not create custom field:\n\n" +
                    "Request PATH: #{request.path}\n\n" +
                    "RAW POST: #{request.raw_post}"
      logger.error e.message
    end
  end
  
  def check_api_key
    if params[:api_key] == Setting.mail_handler_api_key
      authorized = true
      return true
    else
      logger.error 'HOWLING_MINE: Unauthorized Redmine API request.'
      render :status => 403, :text => 'You provided a wrong or no Redmine API key.'
    end
    false
  end
  
  def inject_custom_fields(issues)
    if issues.is_a? Array
      issues.map do |i|
        cfields = {}
        i.available_custom_fields.each do |cf|
          cfields[cf.name] = i.custom_value_for cf.id
        end
        ihash = JSON.parse(i.to_json)
        ihash[:custom_fields] = cfields
        ihash
      end
    else
      cfields = {}
      issues.available_custom_fields.each do |cf|
        cfields[cf.name] = issues.custom_value_for cf.id
      end
      ihash = JSON.parse(issues.to_json)
      ihash[:custom_fields] = cfields
      ihash
    end
  end

end
