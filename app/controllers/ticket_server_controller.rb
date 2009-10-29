class TicketServerController < ApplicationController

  before_filter :check_if_login_required, :except => [:journals, :index, :issue_status, :projects, :issues]
  before_filter :find_or_create_custom_fields

  unloadable  

  def journals
    if authorized? params
      id = params[:issue_id]
      if id
        issue = Issue.find(id.to_i)
        if issue
          render :status => 200, :text => issue.journals.to_json
        else
          render :status => 404, :text => 'Issue not found'
        end
      else
        render :status => 200, :text => Journal.find(:all).to_json
      end
    end
  end

  def issue_status
    if authorized? params
      id = params[:issue_id]
      if id
         issue = Issue.find(id.to_i)
        if issue
          render :status => 200, :text => issue.status.name
        else
          render :status => 404, :text => 'Issue not found'
        end
      else
        render :status => 200, :text => IssueStatus.find(:all).to_json
      end
    end
  end

  def projects
    if authorized?(params)
      render :status => 200, :text => Project.find(:all).to_json
    end
  end

  def issues
    if authorized? params
      issues = Issue.find :all
      render :status => 200, :text => issues.to_json
    end
  end

  def index
    notice = YAML.load(request.raw_post)['ticket']
    redmine_params = YAML.load(notice['params'])
    custom_fields = redmine_params[:custom_fields] 
    if not custom_fields.is_a?(Hash)
      logger.error "REDMINE TICKET SERVER: issue custom fields not valid, skipping"
      custom_fields = {}
    end
    
    if authorized = Setting.mail_handler_api_key == redmine_params[:api_key]
      # redmine objects
      project = Project.find_by_identifier(redmine_params[:project])
      tracker = project.trackers.find_by_name(redmine_params[:tracker])
      author = User.find_by_login(redmine_params[:author]) || User.anonymous

      # error class and message
      error_class = notice['error_class']
      error_message = notice['error_message']

      # build filtered backtrace
      backtrace = notice['back'].blank? ? notice['backtrace'] : notice['back']
      
      # build subject by removing method name and '[RAILS_ROOT]', make sure it fits in a varchar
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
    else
      logger.info 'Unauthorized Redmine API request.'
      render :status => 403, :text => 'You provided a wrong or no Redmine API key.'
    end
  end
  
  protected


  def find_or_create_custom_fields
    if request.path =~ /index|new_ticket/
      notice = YAML.load(request.raw_post)['ticket']
      redmine_params = YAML.load(notice['params'])
      custom_fields = redmine_params[:custom_fields] 

      custom_fields.each do |key,val|
        f = IssueCustomField.find_or_initialize_by_name(key.to_s)
        if f.new_record?
          logger.info "REDMINE_TICKET_SERVER: Creating custom field #{key}"
          f.attributes = {:field_format => 'string', :searchable => true}
          f.save(false)
        end

      end
    end
  end
  
    def authorized?(params)
    if params[:api_key] == Setting.mail_handler_api_key
      authorized = true
      return true
    else
      logger.info 'Unauthorized Redmine API request.'
      render :status => 403, :text => 'You provided a wrong or no Redmine API key.'
    end
    false
  end
end
