class Captain::ConversationCompletionSchema < Schematist::Schema
  boolean :complete, description: 'Whether the conversation is complete and can be closed'
  boolean :expects_customer_reply, description: 'Whether an unanswered question or required information is still expected from the customer.'
  boolean :customer_confirmed, description: 'True only when the customer explicitly confirmed the request was solved. Silence is not confirmation.'
  string :reason, description: 'Brief explanation of why the conversation is complete or incomplete'
end
