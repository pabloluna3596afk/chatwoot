module Limits
  BULK_ACTIONS_LIMIT = 100
  BULK_EXTERNAL_HTTP_CALLS_LIMIT = 25
  URL_LENGTH_LIMIT = 2048 # https://stackoverflow.com/questions/417142
  OUT_OF_OFFICE_MESSAGE_MAX_LENGTH = 10_000
  GREETING_MESSAGE_MAX_LENGTH = 10_000
  CATEGORIES_PER_PAGE = 1000
  AUTO_ASSIGNMENT_BULK_LIMIT = 100
  COMPANY_NAME_LENGTH_LIMIT = 100
  COMPANY_DESCRIPTION_LENGTH_LIMIT = 1000
  MAX_CUSTOM_FILTERS_PER_USER = 1000
  MAX_SAVED_REPORT_PANELS_PER_ACCOUNT = 50
  def self.conversation_message_per_minute_limit
    ENV.fetch('CONVERSATION_MESSAGE_PER_MINUTE_LIMIT', '200').to_i
  end

  def self.search_time_range_limit_days
    days = Integer(ENV.fetch('SEARCH_TIME_RANGE_LIMIT_DAYS', '90'), 10)
    raise ArgumentError, 'SEARCH_TIME_RANGE_LIMIT_DAYS must be a positive integer' unless days.positive?

    days
  rescue ArgumentError
    raise ArgumentError, 'SEARCH_TIME_RANGE_LIMIT_DAYS must be a positive integer'
  end
end
