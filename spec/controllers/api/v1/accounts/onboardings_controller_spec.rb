require 'rails_helper'

RSpec.describe 'Onboarding API', type: :request do
  let(:account) { create(:account, domain: 'example.com') }
  let(:admin) { create(:user, account: account, role: :administrator) }

  describe 'PATCH /api/v1/accounts/{account.id}/onboarding' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        patch "/api/v1/accounts/#{account.id}/onboarding", params: { website: 'acme.com' }, as: :json
        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an agent (non-admin)' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized and does not change the account' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { name: 'Hijacked', website: 'attacker.com' },
              headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
        expect(account.reload.name).not_to eq('Hijacked')
      end

      it 'does not create a help center portal' do
        account.update!(custom_attributes: { 'onboarding_step' => 'account_details' })

        expect do
          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { website: 'attacker.com' },
                headers: agent.create_new_auth_token, as: :json
        end.not_to change(account.portals, :count)
      end
    end

    context 'when finalizing account_details' do
      before { account.update!(custom_attributes: { 'onboarding_step' => 'account_details' }) }

      it 'saves name and locale' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { name: 'Acme Inc', locale: 'fr', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.reload.name).to eq('Acme Inc')
        expect(account.locale).to eq('fr')
      end

      it 'merges custom_attributes' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { website: 'acme.com', industry: 'tech', company_size: '10-50', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json

        attrs = account.reload.custom_attributes
        expect(attrs['website']).to eq('acme.com')
        expect(attrs['industry']).to eq('tech')
        expect(attrs['company_size']).to eq('10-50')
      end

      it 'saves the edited name, business type and country without a website' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { name: 'Mi negocio', business_type: 'appointments', country: 'EC', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.reload.name).to eq('Mi negocio')
        expect(account.custom_attributes).to include('business_type' => 'appointments', 'country' => 'EC')
        expect(account.custom_attributes['website']).to be_blank
      end

      it 'accepts each documented business type and an empty optional country' do
        %w[appointments commerce services other].each do |business_type|
          account.update!(custom_attributes: { 'onboarding_step' => 'account_details' })
          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { business_type: business_type, country: '', onboarding_step: 'account_details' },
                headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(account.reload.custom_attributes).to include('business_type' => business_type, 'country' => '')
        end
      end

      it 'rejects an invalid business type without saving the name or advancing the step' do
        original_name = account.name
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { name: 'Invalid update', business_type: 'restaurant', country: 'EC', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Invalid business type')
        expect(account.reload.name).to eq(original_name)
        expect(account.custom_attributes).to eq('onboarding_step' => 'account_details')
      end

      it 'rejects malformed business types instead of dropping them through strong parameters' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { business_type: ['appointments'], onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload.custom_attributes).to eq('onboarding_step' => 'account_details')
      end

      it 'rejects an invalid country code' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { business_type: 'services', country: 'ZZ', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(response.parsed_body['error']).to eq('Invalid country')
        expect(account.reload.custom_attributes).to eq('onboarding_step' => 'account_details')
      end

      context 'when on cloud (inbox setup is a cloud-only step)' do
        before { allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(true) }

        it 'advances onboarding_step to inbox_setup' do
          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { website: 'acme.com', onboarding_step: 'account_details' },
                headers: admin.create_new_auth_token, as: :json

          expect(account.reload.custom_attributes['onboarding_step']).to eq('inbox_setup')
        end

        it 'does not create a help center portal when website is blank' do
          expect do
            patch "/api/v1/accounts/#{account.id}/onboarding",
                  params: { name: 'Acme Inc', onboarding_step: 'account_details' },
                  headers: admin.create_new_auth_token, as: :json
          end.not_to change(account.portals, :count)
        end

        it 'is idempotent when the account_details completion is replayed' do
          2.times do
            patch "/api/v1/accounts/#{account.id}/onboarding",
                  params: { website: 'acme.com', onboarding_step: 'account_details' },
                  headers: admin.create_new_auth_token, as: :json
          end

          # Replaying step 1 always lands on inbox_setup; it never skips to done.
          expect(account.reload.custom_attributes['onboarding_step']).to eq('inbox_setup')
        end
      end

      context 'when off cloud (inbox setup is skipped)' do
        before { allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(false) }

        it 'finishes onboarding instead of advancing to inbox_setup' do
          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { website: 'acme.com', onboarding_step: 'account_details' },
                headers: admin.create_new_auth_token, as: :json

          expect(account.reload.custom_attributes).not_to have_key('onboarding_step')
        end

        it 'does not auto-create onboarding inboxes' do
          expect(Onboarding::WebWidgetCreationService).not_to receive(:new)

          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { website: 'acme.com', onboarding_step: 'account_details' },
                headers: admin.create_new_auth_token, as: :json
        end
      end
    end

    context 'with onboarding version 2' do
      before do
        account.update!(custom_attributes: { 'onboarding_version' => 2, 'onboarding_step' => 'account_details' })
      end

      [true, false].each do |cloud|
        it "advances to inbox_setup without creating resources when cloud is #{cloud}" do
          allow(ChatwootApp).to receive(:chatwoot_cloud?).and_return(cloud)
          expect(Onboarding::WebWidgetCreationService).not_to receive(:new)

          expect do
            patch "/api/v1/accounts/#{account.id}/onboarding",
                  params: { website: 'acme.com', onboarding_step: 'account_details' },
                  headers: admin.create_new_auth_token, as: :json
          end.not_to change(account.inboxes, :count)

          expect(response).to have_http_status(:success)
          expect(account.reload.custom_attributes).to include('onboarding_version' => 2, 'onboarding_step' => 'inbox_setup')
          expect(response.parsed_body['custom_attributes']).to include('onboarding_version' => 2, 'onboarding_step' => 'inbox_setup')
        end
      end

      it 'does not persist a replayed business update or skip inbox_setup' do
        2.times do |index|
          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { name: "Business #{index}", onboarding_step: 'account_details' },
                headers: admin.create_new_auth_token, as: :json
        end

        expect(account.reload.name).to eq('Business 0')
        expect(account.custom_attributes['onboarding_step']).to eq('inbox_setup')
      end

      it 'ignores an out-of-order completion including an invalid result' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { onboarding_step: 'inbox_setup', inbox_setup_result: 'invalid' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.reload.custom_attributes).to eq('onboarding_version' => 2, 'onboarding_step' => 'account_details')
      end

      context 'when on inbox_setup' do
        before do
          account.update!(custom_attributes: { 'onboarding_version' => 2, 'onboarding_step' => 'inbox_setup' })
        end

        %w[whatsapp_connected skipped].each do |result|
          it "finishes onboarding and records #{result}" do
            inbox = create(:inbox, account: account)

            patch "/api/v1/accounts/#{account.id}/onboarding",
                  params: { onboarding_step: 'inbox_setup', inbox_setup_result: result },
                  headers: admin.create_new_auth_token, as: :json

            expect(response).to have_http_status(:success)
            expect(account.reload.custom_attributes).to eq('onboarding_version' => 2, 'inbox_setup_result' => result)
            attributes = response.parsed_body['custom_attributes']
            expect(attributes['onboarding_version']).to eq(2)
            expect(attributes).not_to include('onboarding_step', 'inbox_setup_result')
            expect(inbox.members).to contain_exactly(admin)
          end
        end

        [nil, '', 'connected', 2, ['skipped'], { value: 'skipped' }].each do |result|
          it "rejects missing or malformed results: #{result.inspect}" do
            patch "/api/v1/accounts/#{account.id}/onboarding",
                  params: { onboarding_step: 'inbox_setup', inbox_setup_result: result },
                  headers: admin.create_new_auth_token, as: :json

            expect(response).to have_http_status(:unprocessable_entity)
            expect(account.reload.custom_attributes).to eq('onboarding_version' => 2, 'onboarding_step' => 'inbox_setup')
          end
        end

        it 'keeps the original result on replay and does not re-enter onboarding' do
          %w[whatsapp_connected skipped invalid].each do |result|
            patch "/api/v1/accounts/#{account.id}/onboarding",
                  params: { onboarding_step: 'inbox_setup', inbox_setup_result: result },
                  headers: admin.create_new_auth_token, as: :json

            expect(response).to have_http_status(:success)
          end

          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { onboarding_step: 'account_details', name: 'Stale' },
                headers: admin.create_new_auth_token, as: :json

          expect(response).to have_http_status(:success)
          expect(account.reload.custom_attributes).to eq('onboarding_version' => 2, 'inbox_setup_result' => 'whatsapp_connected')
          expect(account.name).not_to eq('Stale')
        end
      end
    end

    context 'when replaying account_details after onboarding has finished' do
      before { account.update!(custom_attributes: { 'website' => 'acme.com' }) }

      it 'does not re-enter onboarding or persist the stale payload' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { website: 'stale.com', onboarding_step: 'account_details' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.reload.custom_attributes).not_to have_key('onboarding_step')
        expect(account.custom_attributes['website']).to eq('acme.com')
      end
    end

    context 'when finalizing inbox_setup' do
      before { account.update!(custom_attributes: { 'onboarding_step' => 'inbox_setup' }) }

      it 'clears onboarding_step' do
        inbox = create(:inbox, account: account)

        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { onboarding_step: 'inbox_setup' },
              headers: admin.create_new_auth_token, as: :json

        expect(account.reload.custom_attributes).not_to have_key('onboarding_step')
        expect(inbox.members).to be_empty
      end

      it 'does not create another web widget inbox' do
        expect(Onboarding::WebWidgetCreationService).not_to receive(:new)

        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { onboarding_step: 'inbox_setup' },
              headers: admin.create_new_auth_token, as: :json
      end

      it 'is idempotent when the finalize request is replayed' do
        2.times do
          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { onboarding_step: 'inbox_setup' },
                headers: admin.create_new_auth_token, as: :json
        end

        expect(account.reload.custom_attributes).not_to have_key('onboarding_step')
      end
    end

    context 'when the declared onboarding_step is missing or unknown' do
      before { account.update!(custom_attributes: { 'onboarding_step' => 'invite_team' }) }

      it 'rejects a request without an onboarding_step and changes nothing' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { website: 'acme.com' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
        expect(account.reload.custom_attributes['onboarding_step']).to eq('invite_team')
        expect(account.custom_attributes['website']).to be_nil
      end

      it 'rejects an unknown onboarding_step' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { onboarding_step: 'invite_team' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unprocessable_entity)
      end

      it 'does not create a help center portal' do
        expect do
          patch "/api/v1/accounts/#{account.id}/onboarding",
                params: { website: 'acme.com' },
                headers: admin.create_new_auth_token, as: :json
        end.not_to change(account.portals, :count)
      end
    end

    context 'when completing inbox_setup out of order' do
      before { account.update!(custom_attributes: { 'onboarding_step' => 'account_details' }) }

      it 'does not clear onboarding_step while the account is still on account_details' do
        patch "/api/v1/accounts/#{account.id}/onboarding",
              params: { onboarding_step: 'inbox_setup' },
              headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(account.reload.custom_attributes['onboarding_step']).to eq('account_details')
      end
    end
  end

  describe 'GET /api/v1/accounts/{account.id}/onboarding/help_center_generation' do
    context 'when unauthenticated' do
      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/onboarding/help_center_generation", as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when authenticated as an agent (non-admin)' do
      let(:agent) { create(:user, account: account, role: :agent) }

      it 'returns unauthorized' do
        get "/api/v1/accounts/#{account.id}/onboarding/help_center_generation",
            headers: agent.create_new_auth_token, as: :json

        expect(response).to have_http_status(:unauthorized)
      end
    end

    context 'when no help center generation has started' do
      it 'returns not_started with zero counts' do
        get "/api/v1/accounts/#{account.id}/onboarding/help_center_generation",
            headers: admin.create_new_auth_token, as: :json

        expect(response).to have_http_status(:success)
        expect(response.parsed_body).to include(
          'generation_id' => nil,
          'state' => nil,
          'articles_count' => 0,
          'categories_count' => 0
        )
      end
    end
  end
end
