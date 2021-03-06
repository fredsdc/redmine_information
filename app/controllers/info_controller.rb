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
    @roles = Role.order('builtin, position').all
    @role = Role.find_by_id(params[:role_id])

    @trackers = Tracker.order('position').all
    @tracker = Tracker.find_by_id(params[:tracker_id])

    @workspaces = Workspace.all.sorted
    @workspace = Workspace.find_by_id(params[:workspace_id])

    if @tracker && @tracker.issue_statuses.any?
      @statuses = @tracker.issue_statuses
    end
    @statuses ||= IssueStatus.order('position').all

    if @workspace && @workspace.issue_statuses.any?
      @statuses &= @workspace.issue_statuses
    end

    if (@tracker && @role && @statuses.any?)
      workflows = WorkflowTransition.where(:role_id => @role.id, :tracker_id => @tracker.id).all
      workflows = workflows.where(workspace_id: @workspace[:id]) if @workspace && @workspace[:id]
      @workflows = {}
      @workflows['always'] = workflows.select {|w| !w.author && !w.assignee}
      @workflows['author'] = workflows.select {|w| w.author}
      @workflows['assignee'] = workflows.select {|w| w.assignee}
    end

    @workflow_counts = count_by_tracker_and_role(@trackers, @roles, @workspaces, WorkflowTransition)
    @workflow_all_ng_roles = find_all_ng_roles(@workflow_counts)
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

  private
  def find_all_ng_roles(workflow_counts)
    roles_map = {}
    workflow_counts.each do |tracker, roles|
      roles.each do |role, count|
        roles_map[role] = 0 unless roles_map[role]
        roles_map[role] += count.values.reduce(:+)
      end
    end

    all_ng_roles = []
    roles_map.each {|role, count|
      all_ng_roles << role if (count == 0)
    }

    return all_ng_roles
  end

  private
  def count_by_tracker_and_role(trackers, roles, workspaces, workflow_transitions)
    transitions = workflow_transitions.where.not(old_status_id: 0).group(:tracker_id, :role_id, :workspace_id).count

    result = []
    trackers.each do |tracker|
      t = []
      roles.each do |role|
        count = {}
        workspaces.each do |workspace|
          count[workspace[:id]] = transitions[[tracker.id, role.id, workspace.id]] || 0
        end
        t << [role, count]
      end
      result << [tracker, t]
    end

    result
  end
end
