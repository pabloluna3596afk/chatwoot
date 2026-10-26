# frozen_string_literal: true

require 'rails_helper'

RSpec.describe Migration::ReplaceRetiredCaptainModelsJob do
  let(:account) { create(:account) }

  def store_captain_models(account, models)
    account.update_column(:settings, account.settings.merge('captain_models' => models)) # rubocop:disable Rails/SkipsModelValidations
    account.reload
  end

  before do
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_ENDPOINT').update!(value: nil)
  end

  def save_installation_model(model)
    InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_MODEL').update!(value: model)
  end

  it 'replaces retired text and transcription models and preserves current values' do
    store_captain_models(account, {
                           'editor' => 'gpt-4.1-mini',
                           'assistant' => 'gpt-4.1',
                           'conversation_faq_generation' => 'gpt-4.1-nano',
                           'audio_transcription' => 'gpt-4o-mini-transcribe',
                           'copilot' => 'whisper-1',
                           'help_center_article_generation' => 'gpt-5.2'
                         })
    save_installation_model('gpt-4.1-mini')

    described_class.perform_now

    expect(account.reload.captain_models).to eq(
      'editor' => 'gpt-6-luna',
      'assistant' => 'gpt-6-luna',
      'conversation_faq_generation' => 'gpt-6-luna',
      'audio_transcription' => 'gpt-transcribe',
      'copilot' => 'gpt-transcribe',
      'help_center_article_generation' => 'gpt-5.2'
    )
    expect(InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_MODEL').value).to eq('gpt-6-luna')
  end

  it 'skips account and installation model overrides for a custom endpoint' do
    store_captain_models(account, { 'editor' => 'gpt-4.1-mini' })
    save_installation_model('gpt-4.1')
    InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_ENDPOINT').update!(value: 'https://azure.example.test/openai')

    described_class.perform_now

    expect(account.reload.captain_models).to eq('editor' => 'gpt-4.1-mini')
    expect(InstallationConfig.find_by!(name: 'CAPTAIN_OPEN_AI_MODEL').value).to eq('gpt-4.1')
  end

  it 'tolerates accounts without model settings' do
    account.update_column(:settings, account.settings.except('captain_models')) # rubocop:disable Rails/SkipsModelValidations

    expect { described_class.perform_now }.not_to raise_error
  end

  it 'dry-runs the account mapping without writing settings' do
    store_captain_models(account, { 'editor' => 'gpt-4.1-mini' })
    output = StringIO.new

    described_class.dry_run(output: output)

    expect(output.string).to include("account_id=#{account.id} feature=editor gpt-4.1-mini -> gpt-6-luna")
    expect(account.reload.captain_models).to eq('editor' => 'gpt-4.1-mini')
  end

  it 'is idempotent' do
    store_captain_models(account, { 'editor' => 'gpt-4.1-mini' })

    2.times { described_class.perform_now }

    expect(account.reload.captain_models).to eq('editor' => 'gpt-6-luna')
  end
end
