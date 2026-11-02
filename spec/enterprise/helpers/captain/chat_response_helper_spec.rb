require 'rails_helper'

RSpec.describe Captain::ChatResponseHelper do
  subject(:helper) { host.new }

  let(:host) do
    Class.new do
      include Captain::ChatResponseHelper

      def initialize
        @assistant = Struct.new(:id).new(1)
      end

      def parse(content)
        parse_json_response(content)
      end
    end
  end
  let(:payload) { { 'reasoning' => 'Resumen', 'content' => 'Texto de la respuesta', 'reply_suggestion' => false } }

  it 'parses a normal JSON reply' do
    expect(helper.parse(payload.to_json)).to eq(payload)
  end

  it 'parses a reply wrapped in a json code fence' do
    expect(helper.parse("```json\n#{payload.to_json}\n```")).to eq(payload)
  end

  it 'keeps the first JSON object when the model repeats it twice' do
    doubled = "#{payload.to_json}\n#{payload.merge('content' => 'Otra versión').to_json}"

    expect(helper.parse(doubled)).to eq(payload)
  end

  it 'falls back to the raw text when there is no valid JSON' do
    expect(helper.parse('Hola, no es JSON')).to eq('content' => 'Hola, no es JSON')
  end

  it 'logs response size without logging response content' do
    host.class_eval do
      def build(response)
        build_response(response)
      end

      private

      def parse_json_response(_content) = { 'content' => 'SECRETO-XYZ-123' }

      def apply_credit_usage_metadata(_parsed); end

      def persist_message(_parsed, _role); end

      def captain_v1_assistant? = false
    end
    log_messages = []
    allow(Rails.logger).to receive(:debug) { |&block| log_messages << block.call }
    allow(Rails.logger).to receive(:error)
    response = instance_double(RubyLLM::Message, content: 'SECRETO-XYZ-123')

    helper.build(response)

    expect(log_messages.join).to include('Received response (15 chars)')
    expect(log_messages.join).not_to include('SECRETO-XYZ-123')
  end
end
