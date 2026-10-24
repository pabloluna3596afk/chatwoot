json.payload do
  json.array! @runs do |run|
    json.extract! run, :id, :outcome, :reason, :event_name, :conversation_id, :contact_id, :details, :created_at
  end
end
json.meta do
  json.count @runs.total_count
  json.current_page @runs.current_page
  json.total_pages @runs.total_pages
end
