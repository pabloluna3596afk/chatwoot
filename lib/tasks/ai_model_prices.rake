namespace :ai_model_prices do
  desc 'Import AI model prices from a CSV file'
  task import: :environment do
    file = ENV['FILE'].presence || raise(ArgumentError, 'FILE must point to a CSV file')
    AiModelPrices::ImportService.new(file: file).perform
  end
end
