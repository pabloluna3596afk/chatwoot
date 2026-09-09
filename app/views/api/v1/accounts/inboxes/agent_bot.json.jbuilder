json.agent_bot do
  json.partial! 'api/v1/models/agent_bot', formats: [:json], resource: @agent_bot if @agent_bot.present?
end

agent_bot_inbox = @inbox.agent_bot_inbox
json.schedule_mode agent_bot_inbox&.schedule_mode || 'always'
json.bot_working_hours agent_bot_inbox&.bot_working_hours&.sort_by(&:day_of_week) || [] do |working_hour|
  json.day_of_week working_hour.day_of_week
  json.open_hour working_hour.open_hour
  json.open_minutes working_hour.open_minutes
  json.close_hour working_hour.close_hour
  json.close_minutes working_hour.close_minutes
  json.closed_all_day working_hour.closed_all_day
  json.open_all_day working_hour.open_all_day
end
