# frozen_string_literal: true

require 'rails_helper'

RSpec.describe InstallationConfig do
  subject(:installation_config) { described_class.new(name: 'INSTALLATION_NAME') }

  it { is_expected.to validate_presence_of(:name) }

  describe 'new record defaults' do
    it 'initializes serialized_value with indifferent access' do
      expect(installation_config.serialized_value).to eq({}.with_indifferent_access)
    end

    it 'returns nil for value before assignment' do
      expect(installation_config.value).to be_nil
    end
  end

  describe 'Payphone token encryption' do
    it 'encrypts the token in installation_configs and decrypts it for the server' do
      installation_config.name = 'PAYPHONE_TOKEN'
      installation_config.value = 'payphone-secret-token'
      installation_config.save!

      expect(installation_config.reload.serialized_value['value']).not_to include('payphone-secret-token')
      expect(installation_config.value).to eq('payphone-secret-token')
      expect(installation_config.as_json.to_json).not_to include('payphone-secret-token')

      parameter_filter = ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters)
      filtered = parameter_filter.filter('PAYPHONE_TOKEN' => 'payphone-secret-token')
      expect(filtered['PAYPHONE_TOKEN']).to eq('[FILTERED]')
    end
  end
end
