require 'kconv'

module GraphvizHelper
  include InfoHelper

  def build_json(role, tracker, workflows, name)
    new_issue_status_map = {}
    edges_map = {}
    workflows.each do |t|
      next if t.old_status_id == t.new_status_id
      if t.old_status_id != 0
        key = t.old_status_id.to_s + '-' + t.new_status_id.to_s
        own = role.id == t.role_id
        author = t.author
        assignee = t.assignee
        always = !author && !assignee

        edges_map[key] = {:u => t.old_status_id, :v => t.new_status_id, :roles => []} unless edges_map.include?(key)
        edges_map[key][:own] ||= own
        edges_map[key][:author] ||= own && author
        edges_map[key][:assignee] ||= own && assignee
        edges_map[key][:always] ||= own && always
        edges_map[key][:roles] |= ["role-" + t.role_id.to_s + "-" + name] if eval(name)
      else
        new_issue_status_map[t.new_status_id] = 1
      end
    end
    edges_array = []
    statuses_list = []
    edges_map.each_value do |e|
      cls = 'transOther'
      cls = 'transOwn' if name == 'always' && e[:always]
      cls = 'transOwn' if name == 'author' && e[:author]
      cls = 'transOwn' if name == 'assignee' && e[:assignee]
      cls = [ cls, e[:roles]].join(" ")
      edges_array << { :u => e[:u], :v => e[:v], :value => { :edgeclass => cls } }
      statuses_list |= [e[:u], e[:v]]
    end

    statuses_array = @statuses.map do |s|
      cls = ''
      if tracker.default_status == s
        cls = 'state-new'
      elsif new_issue_status_map.include?(s.id)
        cls = 'state-new-possible'
      elsif s.is_closed
        cls = 'state-closed'
      end
      if workflows.pluck(:old_status_id, :new_status_id).flatten.uniq.include?(s.id)
        cls += ' state-possible'
      end
      if workflows.where(:tracker_id => tracker, :old_status_id => s.id, :new_status_id => s.id).present?
        pre_label = '⟳ '
      else
        pre_label = ''
      end
      { :id => s.id, :value => { :label => pre_label + s.name, :nodeclass => cls } }
    end

    { :nodes => statuses_array, :edges => edges_array }
  end
end
