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
end
