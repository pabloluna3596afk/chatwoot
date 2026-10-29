raise 'PAYPHONE_PREVIEW_FAKE is forbidden in production' if ENV['PAYPHONE_PREVIEW_FAKE'] == '1' && Rails.env.production?
