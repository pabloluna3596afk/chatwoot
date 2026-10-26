# OpenAI retires the GPT-4.1 series and legacy transcription models.
class Migration::ReplaceRetiredCaptainModelsJob < ApplicationJob
  queue_as :async_database_migration

  TEXT_MODEL = Llm::Config::DEFAULT_MODEL
  TRANSCRIPTION_MODEL = 'gpt-transcribe'.freeze
  RETIRED_MODELS = {
    'gpt-4.1' => TEXT_MODEL,
    'gpt-4.1-mini' => TEXT_MODEL,
    'gpt-4.1-nano' => TEXT_MODEL,
    'gpt-4o-mini-transcribe' => TRANSCRIPTION_MODEL,
    'whisper-1' => TRANSCRIPTION_MODEL
  }.freeze

  def perform
    unless Llm::Config.standard_openai_endpoint?
      Rails.logger.info('[retired-captain-models] skipped: custom CAPTAIN_OPEN_AI_ENDPOINT is configured')
      return
    end

    replace_installation_model
    replace_account_models
  end

  def self.dry_run(output: $stdout)
    unless Llm::Config.standard_openai_endpoint?
      output.puts 'Skipped: custom CAPTAIN_OPEN_AI_ENDPOINT is configured'
      return
    end

    Account.find_each do |account|
      account_model_changes(account).each do |feature, (current, replacement)|
        output.puts "account_id=#{account.id} feature=#{feature} #{current} -> #{replacement}"
      end
    end
  end

  def self.account_model_changes(account)
    (account.captain_models || {}).each_with_object({}) do |(feature, current), changes|
      replacement = RETIRED_MODELS[current]
      changes[feature] = [current, replacement] if replacement
    end
  end

  private

  def replace_installation_model
    config = InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_MODEL')
    replacement = RETIRED_MODELS[config&.value]
    config.update!(value: replacement) if replacement
  end

  def replace_account_models
    Account.find_each do |account|
      changes = self.class.account_model_changes(account)
      next if changes.empty?

      models = account.captain_models.transform_values { |model| RETIRED_MODELS.fetch(model, model) }
      # Skip validation on purpose: an unrelated model already outside the allowed list must not block the replacement.
      account.update_column(:settings, account.settings.merge('captain_models' => models)) # rubocop:disable Rails/SkipsModelValidations
    end
  end
end
