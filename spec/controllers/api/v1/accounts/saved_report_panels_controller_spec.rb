require 'rails_helper'

RSpec.describe 'Saved report panels export', type: :request do
  let(:account) { create(:account) }
  let(:administrator) { create(:user, account: account, role: :administrator) }
  let(:aggregate_panel) { create(:saved_report_panel, account: account, created_by: administrator) }
  let(:detail_panel) do
    create(:saved_report_panel, account: account, created_by: administrator,
                                widgets: [{ 'id' => 'w_contacts', 'type' => 'table', 'title' => 'Contactos',
                                            'table_kind' => 'contacts', 'columns' => %w[name] }])
  end

  def export(panel)
    get "/api/v1/accounts/#{account.id}/saved_report_panels/#{panel.id}/export", headers: administrator.create_new_auth_token
  end

  context 'when reports can be downloaded' do
    before { account.enable_features!('report_export') }

    it 'exports a panel with aggregate data' do
      export(aggregate_panel)

      expect(response).to have_http_status(:success)
    end

    it 'does not export a panel with a table of contacts unless customer data can be downloaded too' do
      export(detail_panel)

      expect(response).to have_http_status(:forbidden)
    end

    it 'exports a panel with a table of contacts when customer data can be downloaded' do
      account.enable_features!('customer_data_export')

      export(detail_panel)

      expect(response).to have_http_status(:success)
    end
  end

  context 'when reports cannot be downloaded' do
    before do
      account.disable_features!('report_export')
      account.enable_features!('customer_data_export')
    end

    it 'does not export any panel' do
      export(aggregate_panel)

      expect(response).to have_http_status(:forbidden)
    end
  end
end
