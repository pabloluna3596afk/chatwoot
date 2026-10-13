require 'rails_helper'

RSpec.describe 'Saved report panels preview', type: :request do
  let(:account) { create(:account) }
  let(:admin) { create(:user, account: account, role: :administrator) }
  let(:agent) { create(:user, account: account, role: :agent) }
  let(:params) do
    {
      saved_report_panel: {
        name: 'Draft panel', date_preset: 'last_7_days', filters: [],
        widgets: [{ id: 'draft_metric', type: 'metric', metric: 'conversations_count' }]
      }
    }
  end

  it 'runs the current configuration for an administrator without saving a panel' do
    headers = admin.create_new_auth_token
    expect do
      post "/api/v1/accounts/#{account.id}/saved_report_panels/preview",
           params: params, headers: headers, as: :json
    end.not_to change(SavedReportPanel, :count)

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body['panel_id']).to be_nil
    expect(response.parsed_body['widgets'].first).to include('id' => 'draft_metric', 'value' => 0)
  end

  it 'rejects an agent (unauthorized) without saving a panel' do
    headers = agent.create_new_auth_token
    expect do
      post "/api/v1/accounts/#{account.id}/saved_report_panels/preview",
           params: params, headers: headers, as: :json
    end.not_to change(SavedReportPanel, :count)

    expect(response).to have_http_status(:unauthorized)
  end

  it 'previews valid widgets without a name and preserves fractional timezone offsets' do
    params[:saved_report_panel].delete(:name)
    params[:timezone_offset] = 5.5
    service = instance_double(Reports::PanelRunnerService, perform: { widgets: [] })
    expect(Reports::PanelRunnerService).to receive(:new).with(
      panel: instance_of(SavedReportPanel), account: account, user: admin,
      timezone_offset: 5.5, date_overrides: {}
    ).and_return(service)
    post "/api/v1/accounts/#{account.id}/saved_report_panels/preview", params: params, headers: admin.create_new_auth_token, as: :json
    expect(response).to have_http_status(:ok)
  end

  context 'with dynamic table options' do
    let(:widget) do
      { id: 'table', type: 'table', table_kind: 'pivot', columns: %w[name conversations_count ca:amount__sum ca:amount__avg],
        pivot: { row_attribute: 'created_at', row_granularity: 'week' },
        sort: { column: 'ca:amount__sum', direction: 'asc' },
        top_n: { limit: 5, column: 'ca:amount__sum', include_others: true },
        measure_display: { 'ca:amount__sum' => 'column_percent' },
        column_formats: { 'ca:amount__sum' => { type: 'currency', currency_symbol: 'EUR ', decimals: 2 } } }
    end
    let(:stored) { create(:saved_report_panel, account: account, created_by: admin) }

    it 'round-trips all options on create and update without a migration' do
      params[:saved_report_panel][:widgets] = [widget]
      post "/api/v1/accounts/#{account.id}/saved_report_panels", params: params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      created = account.saved_report_panels.last
      expect(created.widgets.first).to eq(widget.deep_stringify_keys)
      widget[:pivot] = { row_attribute: 'ca:segment' }
      patch "/api/v1/accounts/#{account.id}/saved_report_panels/#{created.id}", params: params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
      expect(created.reload.widgets.first['pivot']).to eq('row_attribute' => 'ca:segment')
    end

    invalid_options = [
      { table_kind: 'agent_summary' },
      { pivot: { column_attribute: 'ca:segment' } },
      { pivot: nil },
      { pivot: { row_attribute: 'agent', column_attribute: 5 } },
      { pivot: { row_attribute: 'agent', column_attribute: 'ca:segment', column_values: [5] } },
      { pivot: { row_attribute: 'agent', column_attribute: 'ca:segment', column_values: Array.new(13, 'A') } },
      { pivot: { row_attribute: 'agent', show_row_totals: 'true' } },
      { columns: %w[name ca:amount] },
      { columns: %w[name ca:amount__count__eq__10] },
      { columns: %w[name name conversations_count] },
      { columns: ['name', false] },
      { columns: [] },
      { pivot: { row_attribute: 'invalid' } },
      { pivot: { row_attribute: false } },
      { pivot: { row_attribute: 'agent', row_granularity: 'day' } },
      { pivot: { row_attribute: 'created_at', row_granularity: 'year' } },
      { sort: { column: 'missing', direction: 'asc' } },
      { sort: { column: 'name', direction: 'up' } },
      { sort: 'name' },
      { top_n: { limit: '5', column: 'conversations_count', include_others: false } },
      { top_n: { limit: 3, column: 'conversations_count', include_others: false } },
      { top_n: { limit: 5.0, column: 'conversations_count', include_others: false } },
      { top_n: { limit: 5, column: 'name', include_others: false } },
      { top_n: { limit: 5, column: 'conversations_count', include_others: 'false' } },
      { measure_display: { 'ca:amount__avg' => 'row_percent' } },
      { measure_display: { 'missing' => 'value' } },
      { measure_display: [] },
      { column_formats: { 'ca:amount__sum' => { type: 'currency', decimals: 3 } } },
      { column_formats: { 'ca:amount__sum' => { type: 'currency', decimals: '2' } } },
      { column_formats: { 'ca:amount__sum' => { type: 'currency', currency_symbol: 1 } } },
      { column_formats: { 'ca:amount__sum' => { type: 'text' } } }
    ]

    %w[create update preview].each do |action|
      context "when #{action}" do
        invalid_options.each do |invalid|
          it "rejects #{invalid.inspect} with 422 before running or persisting" do
            widget.merge!(invalid)
            params[:saved_report_panel][:widgets] = [widget]
            expect(Reports::PanelRunnerService).not_to receive(:new)
            if action == 'update'
              before_widgets = stored.widgets
              patch "/api/v1/accounts/#{account.id}/saved_report_panels/#{stored.id}", params: params, headers: admin.create_new_auth_token, as: :json
              expect(stored.reload.widgets).to eq(before_widgets)
            else
              path = "/api/v1/accounts/#{account.id}/saved_report_panels#{action == 'preview' ? '/preview' : ''}"
              expect { post path, params: params, headers: admin.create_new_auth_token, as: :json }.not_to change(SavedReportPanel, :count)
            end
            expect(response).to have_http_status(:unprocessable_entity)
          end
        end
      end
    end

    it 'rejects Others with contact measures at the request boundary' do
      widget[:columns] << 'contact_ca:amount__sum'
      params[:saved_report_panel][:widgets] = [widget]
      post "/api/v1/accounts/#{account.id}/saved_report_panels/preview", params: params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
    end

    it 'accepts additive contact percentages and expanded sort/Top N keys' do
      widget[:columns] << 'contact_ca:amount__sum'
      widget[:pivot] = { row_attribute: 'inbox', column_attribute: 'ca:segment', column_values: ['A'] }
      widget[:sort][:column] = 'ca:amount__sum__pv__A'
      widget[:top_n] = { limit: nil, column: 'ca:amount__sum__pv__A', include_others: false }
      widget[:measure_display] = { 'contact_ca:amount__sum' => 'row_percent' }
      params[:saved_report_panel][:widgets] = [widget]
      post "/api/v1/accounts/#{account.id}/saved_report_panels", params: params, headers: admin.create_new_auth_token, as: :json
      expect(response).to have_http_status(:success)
    end
  end
end
