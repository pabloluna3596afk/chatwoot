class Captain::Llm::EmbeddingService
  include Integrations::LlmInstrumentation

  class EmbeddingsError < StandardError; end

  def initialize(account_id: nil)
    Llm::Config.initialize!
    @account_id = account_id
    @embedding_model = self.class.embedding_model
  end

  def self.embedding_model
    InstallationConfig.find_by(name: 'CAPTAIN_EMBEDDING_MODEL')&.value.presence || LlmConstants::DEFAULT_EMBEDDING_MODEL
  end

  def get_embedding(content, model: @embedding_model)
    return [] if content.blank?

    account = Account.find_by(id: @account_id)
    return perform_embedding(content, model) unless account

    Llm::UsageContext.with(account: account, feature: 'embedding', units: Llm::UnitCosts.fetch(:embedding)) do
      perform_embedding(content, model)
    end
  rescue RubyLLM::Error => e
    Rails.logger.error "Embedding API Error: #{e.message}"
    raise EmbeddingsError, "Failed to create an embedding: #{e.message}"
  end

  private

  def perform_embedding(content, model)
    instrument_embedding_call(instrumentation_params(content, model)) do
      RubyLLM.embed(content, model: model)
    end.vectors
  end

  def instrumentation_params(content, model)
    {
      span_name: 'llm.captain.embedding',
      model: model,
      provider: 'openai',
      input: content,
      feature_name: 'embedding',
      account_id: @account_id
    }
  end
end
