class Captain::Tools::Copilot::GetDataService < Captain::Tools::BaseTool
  def self.name
    'get_data'
  end

  RESOURCES_DESCRIPTION = Captain::Copilot::Resources.all.map(&:help).join("\n").freeze
  description <<~DESCRIPTION
    Count, aggregate, and group conversations or contacts without returning records. Use created_after/created_before or last_activity_after/last_activity_before for ISO 8601 or relative date bounds in the account timezone. Date ranges are limited to 366 days. Group conversations by inbox, assignee, team, day, or week when useful, for example: "how many conversations arrived this week by inbox?" This tool never lists records; use search_conversation to retrieve conversation records.
    Resources:
    #{RESOURCES_DESCRIPTION}
  DESCRIPTION
  parameters type: 'object', required: %w[resource filters], additionalProperties: false,
             properties: {
               resource: { type: 'string', enum: Captain::Copilot::Resources.all.map { |resource| resource::NAME } },
               filters: { type: 'object', description: 'Typed filters allowed for the selected resource' },
               group_by: { type: 'string', description: 'Allowed resource group or day/week/month/year temporal grouping' },
               aggregate: {
                 type: 'object', additionalProperties: false, required: %w[function],
                 properties: {
                   function: { type: 'string', enum: %w[count sum avg min max] },
                   key: { type: 'string', description: 'Required for sum, avg, min, or max; must be numeric custom attribute' }
                 }
               }
             }

  def execute(resource:, filters:, group_by: nil, aggregate: nil)
    @get_data_calls ||= 0
    @get_data_calls += 1
    if @get_data_calls > Captain::Copilot::CollectionService::MAX_TOOL_CALLS
      return {
        error: "get_data allows at most #{Captain::Copilot::CollectionService::MAX_TOOL_CALLS} calls per turn. " \
               'It returns counts only; use search_conversation to retrieve conversation records.'
      }
    end

    Captain::Copilot::CollectionService.new(account: @assistant.account, user: @user)
                                       .create(resource: resource, filters: filters, group_by: group_by, aggregate: aggregate)
  rescue ArgumentError, ActiveRecord::RecordNotFound => e
    { error: "#{e.message}. get_data returns counts only; use search_conversation to retrieve conversation records." }
  end

  def active?
    user_has_permission('conversation_manage') || user_has_permission('conversation_unassigned_manage') ||
      user_has_permission('conversation_participating_manage') || user_has_permission('contact_manage')
  end
end
