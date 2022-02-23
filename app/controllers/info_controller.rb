require 'rails/info'

class InfoController < ApplicationController
  unloadable

  before_action :require_login

  helper :info
  include InfoHelper
  helper :graphviz
  include GraphvizHelper

  def permissions
    @roles = Role.sorted.all
    @permissions = Redmine::AccessControl.permissions.select { |p| !p.public? }
  end

  def workflows
    @workspaces = Workspace.all.sorted
    @workspace = Workspace.find_by_id(params[:workspace_id]) || Workspace.first

    @roles = Role.where(id: WorkflowTransition.where(workspace_id: @workspace.id).pluck(:role_id)).sorted
    @role = Role.find_by_id(params[:role_id])

    @trackers = Tracker.where(id: WorkflowTransition.where(workspace_id: @workspace[:id]).pluck(:tracker_id)).sorted
    @tracker = Tracker.find_by_id(params[:tracker_id])

    @statuses = @tracker ? (@tracker.issue_statuses & @workspace.issue_statuses) : []

    if (@tracker && @statuses.any?)
      @workflows = WorkflowTransition.where(:tracker_id => @tracker.id, :workspace_id => @workspace.id)
    end

    @workflow_counts = WorkflowTransition.where.not(old_status_id: 0).group(:tracker_id, :role_id, :workspace_id).count
  end

  def settings
    # Mail Notification
    @notifiables = []
    Redmine::Notifiable.all.each {|notifiable|
      if notifiable.parent.present?
        next	if (Setting.notified_events.include?(notifiable.parent))
      end
      @notifiables << notifiable
    }
    @deliveries = ActionMailer::Base.perform_deliveries

    # Repository
    if commit_update_keywords_supported?
      @commit_update_keywords = Setting.commit_update_keywords_array
      @commit_update_keywords.each do |rule|
        if rule['keywords'].is_a?(Array)
          rule['keywords_string'] = rule['keywords'].join(",")
        end
        if rule.has_key?('if_tracker_id')
          tracker = Tracker.find_by_id(rule['if_tracker_id'])
          rule['if_tracker_name'] = tracker.name if (tracker)
        end
        if rule.has_key?('status_id')
          status = IssueStatus.find_by_id(rule['status_id'])
          rule['status_name'] = status.name if (status)
        end
      end
    end

    @commit_cross_project_ref = Setting[:commit_cross_project_ref]
    if (@commit_cross_project_ref)
      @commit_cross_project_ref = (0 < @commit_cross_project_ref.to_i)
    end
    @commit_logtime_enabled = Setting[:commit_logtime_enabled]
    if (@commit_logtime_enabled)
      @commit_logtime_enabled = (0 < @commit_logtime_enabled.to_i)
    end
    @commit_logtime_activity_name = l(:label_default)
    if (@commit_logtime_enabled)
      aid = Setting[:commit_logtime_activity_id]
      if (aid and 0 < aid.to_i)
        activity = TimeEntryActivity.find_by_id(aid)
        @commit_logtime_activity_name = activity.name	if (activity)
      end
    end
  end

  def plugins
    @plugins = Redmine::Plugin.all
  end

  def show
    @icat = params[:id]
    case @icat
    when 'permissions'; permissions;
    when 'workflows'; workflows;
    when 'settings'; settings;
    when 'plugins'; plugins;
    when 'version'
      @db_adapter_name = ActiveRecord::Base.connection.adapter_name
    end
  end

  def index
  end
end
