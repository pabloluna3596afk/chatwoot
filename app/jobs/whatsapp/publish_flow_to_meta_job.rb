module Whatsapp
  class PublishFlowToMetaJob < ApplicationJob
    queue_as :default
    MAX_RETRIES = 3
    NETWORK_ERROR_CODES = [Net::HTTPServerError, Timeout::Error, Errno::ECONNREFUSED].freeze

    def perform(flow_id, account_id)
      @flow = WhatsappFlow.find(flow_id)
      @account = Account.find(account_id)

      discover_cloud_channels.each do |channel|
        publish_to_waba(channel)
      end
    rescue StandardError => e
      handle_job_error(e)
    end

    private

    def discover_cloud_channels
      # Get all Cloud WABA channels for the account, de-duplicated by business_account_id
      @account.channels.where(provider: 'whatsapp').select { |ch|
        ch.provider_config&.dig('business_account_id').present?
      }.uniq { |ch| ch.provider_config['business_account_id'] }
    end

    def publish_to_waba(channel)
      waba_id = channel.provider_config['business_account_id']

      begin
        service = Whatsapp::Flows::PublishToMetaService.new(@flow, channel)
        result = service.perform

        if result[:success]
          log_success(waba_id, result)
        else
          log_error(waba_id, result)
        end
      rescue StandardError => e
        handle_waba_error(channel, e)
      end
    end

    def handle_waba_error(channel, error)
      waba_id = channel.provider_config['business_account_id']

      if is_retryable_error?(error)
        # Retry with exponential backoff
        retry_count = (attempts || 0)
        if retry_count < MAX_RETRIES
          delay = [1, 5, 30][retry_count].seconds
          self.class.set(wait: delay).perform_later(@flow.id, @account.id)
          log_retry(waba_id, retry_count, error)
        else
          log_permanent_failure(waba_id, error)
        end
      else
        # Validation errors: don't retry
        log_error(waba_id, { success: false, error: error.message })
      end
    end

    def is_retryable_error?(error)
      NETWORK_ERROR_CODES.any? { |code| error.is_a?(code) } ||
        error.message.include?('timeout') ||
        error.message.include?('connection')
    end

    def log_success(waba_id, result)
      Rails.logger.info("Flow #{@flow.id} published to WABA #{waba_id}: #{result[:status]}")
    end

    def log_error(waba_id, result)
      Rails.logger.warn("Flow #{@flow.id} publication to WABA #{waba_id} failed: #{result[:error]}")
    end

    def log_retry(waba_id, attempt, error)
      Rails.logger.warn("Flow #{@flow.id} publication to WABA #{waba_id} retry #{attempt + 1}/#{MAX_RETRIES}: #{error.message}")
    end

    def log_permanent_failure(waba_id, error)
      Rails.logger.error("Flow #{@flow.id} publication to WABA #{waba_id} permanently failed: #{error.message}")
    end

    def handle_job_error(error)
      Rails.logger.error("PublishFlowToMetaJob failed for flow #{@flow&.id} in account #{@account&.id}: #{error.message}")
      raise error
    end
  end
end
