# frozen_string_literal: true

namespace :captain do
  namespace :models do
    desc 'List retired Captain model replacements without writing changes'
    task dry_run: :environment do
      Migration::ReplaceRetiredCaptainModelsJob.dry_run
    end
  end
end
