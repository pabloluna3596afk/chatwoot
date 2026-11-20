json.id @agent_session.id
json.message_id @agent_session.result_id
technical = Captain::Decisions::TechnicalSummary.build(
  user: Current.user, account_user: Current.account_user,
  details: Captain::Decisions::TechnicalSummary.session_details(@agent_session)
)
json.technical technical
json.summary Captain::Decisions::SessionSummary.build(@agent_session)
json.citations @citations do |citation|
  json.id citation.id
  json.title citation.name
  # display_url resolves uploaded PDFs to their blob URL; external_link holds a
  # "PDF: ..." placeholder for those. Guard on scheme so placeholders render as
  # plain text instead of dead anchors.
  link = citation.display_url
  json.link Captain::Decisions::Sources.safe_link(link)
end
json.used_faqs @used_faqs do |faq|
  json.id faq.id
  json.title faq.question
end
json.scenarios @scenario_titles do |id, title|
  json.id id
  json.title title
end
