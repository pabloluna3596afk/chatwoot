json.id resource.id
json.name resource.name
json.description resource.description
json.thumbnail resource.avatar_url
json.outgoing_url resource.outgoing_url unless resource.system_bot?
json.bot_type resource.bot_type
json.bot_config resource.bot_config
json.account_id resource.account_id
json.access_token resource.access_token if resource.access_token.present? && Current.account_user&.administrator?

# Only ships the secret when the bot has its own webhook URL — that's the
# only case where an admin has a real system to configure it into. When
# outgoing_url is blank the bot runs on Panel AI's default and nobody needs
# this value, so it never leaves the server (see AgentBot#effective_outgoing_url).
json.secret resource.secret if !resource.system_bot? && resource.outgoing_url.present? && Current.account_user&.administrator?
json.system_bot resource.system_bot?
