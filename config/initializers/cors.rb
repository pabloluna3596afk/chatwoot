# config/initializers/cors.rb
# ref: https://github.com/cyu/rack-cors

# font cors issue with CDN
# Ref: https://stackoverflow.com/questions/56960709/rails-font-cors-policy
# The public plan catalog feeds the marketing website only, so unlike the other
# public endpoints it is limited to the website origins. Override with a
# comma separated PLANS_CORS_ORIGINS.
PLANS_CORS_DEFAULT_ORIGINS = 'https://paluhub.com,https://www.paluhub.com'.freeze
plans_cors_origins = ENV.fetch('PLANS_CORS_ORIGINS', PLANS_CORS_DEFAULT_ORIGINS).split(',').map(&:strip).compact_blank
# Every other /public/api/* path keeps the wildcard rule; the plans path is excluded from it.
public_api_except_plans = %r{\A/public/api/(?!v1/plans(?:\.json)?/?\z)}

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    origins(*plans_cors_origins)
    resource '/public/api/v1/plans', headers: %w[Accept If-None-Match], methods: [:get, :options], expose: %w[ETag], vary: 'Origin'
  end

  allow do
    origins '*'
    resource '/packs/*', headers: :any, methods: [:get, :options]
    resource '/audio/*', headers: :any, methods: [:get, :options]
    # Make the public endpoints accessible to the frontend
    resource public_api_except_plans, headers: :any, methods: :any

    if ActiveModel::Type::Boolean.new.cast(ENV.fetch('CW_API_ONLY_SERVER', false)) || Rails.env.development?
      resource '*', headers: :any, methods: :any, expose: %w[access-token client uid expiry]
    end

    if ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENABLE_API_CORS', false))
      resource '/api/*', headers: :any, methods: :any, expose: %w[access-token client uid expiry]
    end
  end
end

################################################
######### Action Cable Related Config ##########
################################################

# Mount Action Cable outside main process or domain
# Rails.application.config.action_cable.mount_path = nil
# Rails.application.config.action_cable.url = 'wss://example.com/cable'
# Rails.application.config.action_cable.allowed_request_origins = [ 'http://example.com', /http:\/\/example.*/ ]

# To Enable connecting to the API channel public APIs
# ref : https://medium.com/@emikaijuin/connecting-to-action-cable-without-rails-d39a8aaa52d5
Rails.application.config.action_cable.disable_request_forgery_protection = true
