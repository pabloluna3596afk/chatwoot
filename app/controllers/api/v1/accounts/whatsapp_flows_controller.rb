module Api
  module V1
    module Accounts
      class WhatsappFlowsController < Api::V1::Accounts::BaseController
        before_action :set_whatsapp_flow, only: [:show, :update, :publish, :publication_status, :test, :retry_publish]
        before_action :admin_only_for_writes, only: [:create, :update, :publish, :test, :retry_publish]

        def index
          @whatsapp_flows = @account.whatsapp_flows.includes(:whatsapp_flow_publications)
          render json: @whatsapp_flows
        end

        def show
          render json: @whatsapp_flow
        end

        def create
          @whatsapp_flow = @account.whatsapp_flows.build(whatsapp_flow_params)

          if @whatsapp_flow.save
            render json: @whatsapp_flow, status: :created
          else
            render json: { errors: @whatsapp_flow.errors }, status: :unprocessable_entity
          end
        end

        def update
          if @whatsapp_flow.update(whatsapp_flow_params)
            render json: @whatsapp_flow
          else
            render json: { errors: @whatsapp_flow.errors }, status: :unprocessable_entity
          end
        end

        def publish
          Whatsapp::PublishFlowToMetaJob.perform_later(@whatsapp_flow.id, @account.id)
          render json: publication_status_response, status: :accepted
        end

        def publication_status
          render json: publication_status_response
        end

        def test
          phone_number = params.require(:phone_number)
          channel_id = params.require(:channel_id)
          channel = @account.channels.find(channel_id)

          service = Whatsapp::Flows::TestFlowService.new(@whatsapp_flow, channel, phone_number)
          result = service.perform

          if result[:success]
            render json: { success: true, message_id: result[:message_id] }
          else
            render json: { success: false, error: result[:error] }, status: :bad_request
          end
        end

        def retry_publish
          waba_id = params.require(:waba_id)
          publication = @whatsapp_flow.whatsapp_flow_publications.find_by(waba_id: waba_id)

          return render json: { error: 'Publication not found' }, status: :not_found unless publication

          channel = find_channel_for_waba(waba_id)
          return render json: { error: 'Channel not found for this WABA' }, status: :not_found unless channel

          service = Whatsapp::Flows::PublishToMetaService.new(@whatsapp_flow, channel)
          result = service.perform

          render json: publication_status_response
        end

        private

        def set_whatsapp_flow
          @whatsapp_flow = @account.whatsapp_flows.find(params[:id])
        end

        def whatsapp_flow_params
          params.require(:whatsapp_flow).permit(:name, :flow_json, flow_categories: [])
        end

        def publication_status_response
          publications = @whatsapp_flow.whatsapp_flow_publications.map do |pub|
            {
              waba_id: pub.waba_id,
              status: pub.status,
              meta_flow_id: pub.meta_flow_id,
              validation_errors: pub.validation_errors,
              published_at: pub.published_at
            }
          end

          { flow_id: @whatsapp_flow.id, publications: publications }
        end

        def find_channel_for_waba(waba_id)
          @account.channels.where(provider: 'whatsapp').find do |ch|
            ch.provider_config&.dig('business_account_id') == waba_id
          end
        end

        def admin_only_for_writes
          return if @current_user&.admin?
          render json: { error: 'Unauthorized' }, status: :unauthorized
        end
      end
    end
  end
end
