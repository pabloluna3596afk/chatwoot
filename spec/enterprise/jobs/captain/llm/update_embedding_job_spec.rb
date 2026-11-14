require 'rails_helper'

RSpec.describe Captain::Llm::UpdateEmbeddingJob do
  let(:response) { create(:captain_assistant_response) }
  let(:embedding) { [1.0] + Array.new(1535, 0.0) }
  let(:service) { instance_double(Captain::Llm::EmbeddingService, get_embedding: embedding) }

  before { allow(Captain::Llm::EmbeddingService).to receive(:new).with(account_id: response.account_id).and_return(service) }

  it 'updates the vector using the supplied content' do
    described_class.perform_now(response, 'Pregunta: respuesta')
    expect(service).to have_received(:get_embedding).with('Pregunta: respuesta')
    expect(response.reload.embedding).to eq(embedding)
  end

  it 'rejects an invalid embedding without changing the stored vector' do
    previous = response.reload.embedding
    allow(service).to receive(:get_embedding).and_return([0.1, 0.2])
    expect { described_class.perform_now(response, 'contenido') }.to raise_error do |error|
      expect(error.class.name).to eq('Neighbor::Error')
    end
    expect(response.reload.embedding).to eq(previous)
  end

  it 'rejects empty content when the embedding service returns its empty vector' do
    allow(service).to receive(:get_embedding).with(nil).and_return([])
    expect { described_class.perform_now(response, nil) }.to raise_error do |error|
      expect(error.class.name).to eq('Neighbor::Error')
    end
  end

  it 'attributes usage to the response account and leaves other accounts untouched' do
    other_response = create(:captain_assistant_response)
    previous = other_response.reload.embedding
    described_class.perform_now(response, 'contenido')
    expect(Captain::Llm::EmbeddingService).to have_received(:new).with(account_id: response.account_id)
    expect(other_response.reload.embedding).to eq(previous)
  end
end
