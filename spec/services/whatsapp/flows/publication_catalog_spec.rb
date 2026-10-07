require 'rails_helper'

RSpec.describe Whatsapp::Flows::PublicationCatalog do
  let(:account) { create(:account) }
  let(:flow) { create(:whatsapp_flow, account: account) }
  let(:catalog) { described_class.new(account) }
  let!(:channel) do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).tap do |record|
      record.update!(provider_config: record.provider_config.merge('business_account_id' => '111', 'api_key' => 'secret-not-for-payload'))
    end
  end

  before do
    create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false).tap do |record|
      record.update!(provider_config: record.provider_config.merge('business_account_id' => '222'))
    end
  end

  it 'counts distinct WABAs, including multiple numbers without duplicate publications' do
    duplicate = create(:channel_whatsapp, account: account, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    duplicate.update!(provider_config: duplicate.provider_config.merge('business_account_id' => '111'))
    flow.whatsapp_flow_publications.create!(account: account, waba_id: '111', status: 'published')
    expect(catalog.summary(catalog.flows.find(flow.id))).to eq(state: 'partial', total: 2, published: 1, errors: 0)
    detail = catalog.detail(flow, page: 1, per_page: 5)
    expect(detail[:rows].find { |row| row['waba_id'] == '111' }['numbers'].size).to eq(2)
    expect(detail.to_json).not_to include('api_key', 'secret-not-for-payload', 'provider_config')
  end

  it 'reports all published and preserves the unpublished changes cue' do
    %w[111 222].each do |waba|
      flow.whatsapp_flow_publications.create!(account: account, waba_id: waba, status: 'published', published_at: flow.updated_at - 1.second)
    end
    entry = catalog.flows.find(flow.id)
    expect(catalog.summary(entry)).to eq(state: 'published', total: 2, published: 2, errors: 0)
    expect(entry.catalog_unpublished).to be true
  end

  %w[blocked throttled].each do |status|
    it "counts #{status} as an error and filters it in the detail" do
      flow.whatsapp_flow_publications.create!(account: account, waba_id: '111', status: status)
      expect(catalog.summary(catalog.flows.find(flow.id))).to eq(state: 'error', total: 2, published: 0, errors: 1)
      expect(catalog.detail(flow, page: 1, per_page: 5, state: 'error')[:rows].pluck('state')).to eq([status])
    end
  end

  it 'counts Meta validation errors ahead of published successes' do
    flow.whatsapp_flow_publications.create!(account: account, waba_id: '111', status: 'published', validation_errors: [{ 'message' => 'Invalid' }])
    flow.whatsapp_flow_publications.create!(account: account, waba_id: '222', status: 'published')
    expect(catalog.summary(catalog.flows.find(flow.id))).to eq(state: 'error', total: 2, published: 1, errors: 1)
    expect(catalog.filter_state(catalog.flows, 'error').pluck(:id)).to eq([flow.id])
  end

  it 'keeps retired publications in detail while the summary says none sent' do
    flow.whatsapp_flow_publications.create!(account: account, waba_id: '111', status: 'deprecated')
    expect(catalog.summary(catalog.flows.find(flow.id))).to eq(state: 'none', total: 2, published: 0, errors: 0)
    expect(catalog.detail(flow, page: 1, per_page: 5, state: 'deprecated')[:rows].pluck('waba_id')).to eq(['111'])
  end

  it 'searches WABA IDs and phones and paginates on the server' do
    detail = catalog.detail(flow, page: 2, per_page: 1)
    expect(detail[:meta]).to eq(current_page: 2, per_page: 1, total_count: 2)
    expect(detail[:rows].pluck('waba_id')).to eq(['222'])
    expect(catalog.detail(flow, page: 1, per_page: 5, search: '111')[:rows].pluck('waba_id')).to eq(['111'])
    expect(catalog.detail(flow, page: 1, per_page: 5, search: channel.phone_number)[:rows]).not_to be_empty
    expect(catalog.detail(flow, page: 1, per_page: 5, search: '%')[:rows]).to be_empty
  end

  it 'excludes other accounts, removed WABAs and non-Cloud numbers' do
    create(:channel_whatsapp, provider: 'whatsapp_cloud', validate_provider_config: false, sync_templates: false)
    create(:channel_whatsapp, account: account, provider: 'default', validate_provider_config: false, sync_templates: false)
    flow.whatsapp_flow_publications.create!(account: account, waba_id: 'removed', status: 'blocked')
    expect(catalog.summary(catalog.flows.find(flow.id))).to eq(state: 'none', total: 2, published: 0, errors: 0)
    expect(catalog.detail(flow, page: 1, per_page: 5)[:meta][:total_count]).to eq(2)
  end
end
