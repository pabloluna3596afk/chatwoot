json.billing_provider account.billing_provider
json.subscribed_features account.subscribed_features

if @current_account_user.administrator? && account.feature_enabled?('captain_integration')
  cap = Captain::TemplateDailyCap.new(account)
  json.captain_template_cap do
    json.cap cap.daily_cap
    json.used cap.used
  end
end
