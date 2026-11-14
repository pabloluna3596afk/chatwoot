namespace :captain do
  desc 'Evaluación manual de Captain en desarrollo (requiere CAPTAIN_EVAL=1; consume IA real)'
  task eval: :environment do
    result = Captain::Eval::Runner.new.perform
    puts "Informe: #{result.fetch(:markdown)}"
    puts "JSON: #{result.fetch(:json)}"
    puts "Totales: #{result.fetch(:totals).to_json}"
  end
end
