namespace :plans do # rubocop:disable Metrics/BlockLength
  desc 'Seed the real ChatHub pricing plans (Prueba, Inicio, Crecimiento, Negocio, Escala, Developer) as Plan rows'
  task seed: :environment do # rubocop:disable Metrics/BlockLength
    common = {
      addon_agent_price: 18,
      addon_bot_price: 35,
      credit_unit_price: 0.025
    }

    plans = [
      {
        name: 'Prueba', slug: 'prueba', description: 'Plan de prueba gratuito, 15 dias.',
        captain_daily_tests: 0,
        captain_copilot_responses: 0, captain_internal_calls: 0,
        monthly_messages: 200, storage_mb: 1, max_documents: 1, max_captain_assistants: 1, max_human_agents: 1,
        max_inboxes: 1, max_emails_per_day: 50,
        price_monthly: 0, price_yearly: 0, trial_days: 15, trial_messages: 200, display_order: 0,
        is_default_trial: true
      },
      {
        name: 'Inicio', slug: 'inicio', description: 'Para equipos que estan arrancando con IA.',
        captain_daily_tests: 10,
        captain_copilot_responses: 500, captain_internal_calls: 500,
        monthly_messages: 1_000, storage_mb: 100, max_documents: 100, max_captain_assistants: 1, max_human_agents: 2,
        max_inboxes: 2, max_emails_per_day: 500,
        price_monthly: 79, price_yearly: 79 * 12, trial_days: 0, trial_messages: 0, display_order: 1,
        is_default_trial: false
      },
      {
        name: 'Crecimiento', slug: 'crecimiento', description: 'El mas elegido. Precio regular USD 149, promocional USD 119.',
        captain_daily_tests: 20,
        captain_copilot_responses: 1_500, captain_internal_calls: 1_500,
        monthly_messages: 3_000, storage_mb: 250, max_documents: 250, max_captain_assistants: 3, max_human_agents: 5,
        max_inboxes: 5, max_emails_per_day: 2_000,
        price_monthly: 119, price_yearly: 119 * 12, trial_days: 0, trial_messages: 0, display_order: 2,
        is_default_trial: false
      },
      {
        name: 'Negocio', slug: 'negocio', description: 'Para equipos con volumen alto de conversaciones.',
        captain_daily_tests: 35,
        captain_copilot_responses: 4_000, captain_internal_calls: 4_000,
        monthly_messages: 8_000, storage_mb: 1024, max_documents: 1024, max_captain_assistants: 5, max_human_agents: 15,
        max_inboxes: 10, max_emails_per_day: 5_000,
        price_monthly: 299, price_yearly: 299 * 12, trial_days: 0, trial_messages: 0, display_order: 3,
        is_default_trial: false
      },
      {
        name: 'Escala', slug: 'escala', description: 'Para operaciones grandes, multiples equipos.',
        captain_daily_tests: 50,
        captain_copilot_responses: 10_000, captain_internal_calls: 10_000,
        monthly_messages: 20_000, storage_mb: 2048, max_documents: 2048, max_captain_assistants: 15, max_human_agents: 40,
        max_inboxes: 25, max_emails_per_day: 15_000,
        price_monthly: 599, price_yearly: 599 * 12, trial_days: 0, trial_messages: 0, display_order: 4,
        is_default_trial: false
      },
      {
        name: 'Developer', slug: 'developer', description: 'BYOK (trae tu propia llave de IA), sin cupo de mensajes incluidos.',
        captain_daily_tests: 10,
        captain_copilot_responses: nil, captain_internal_calls: nil,
        monthly_messages: 0, storage_mb: 100, max_documents: 100, max_captain_assistants: 3, max_human_agents: 5,
        max_inboxes: 3, max_emails_per_day: 1_000,
        price_monthly: 49, price_yearly: 49 * 12, trial_days: 0, trial_messages: 0, display_order: 5,
        is_default_trial: false
      }
    ]

    plans.each do |attrs|
      plan = Plan.find_or_initialize_by(slug: attrs[:slug])
      was_new = plan.new_record?
      unless was_new
        puts "Unchanged: #{plan.name} (#{plan.slug})"
        next
      end

      plan.assign_attributes(common.merge(attrs).merge(
                               is_active: true, is_public: attrs[:slug] != 'developer', coming_soon: !attrs[:is_default_trial]
                             ))
      plan.save!
      puts "Created: #{plan.name} (#{plan.slug})"
    end
  end

  desc 'Fill only NULL AI bag limits on existing plans (DRY_RUN=true to preview)'
  task fill_ai_bags: :environment do
    defaults = {
      'prueba' => { captain_copilot_responses: 0, captain_internal_calls: 0 },
      'inicio' => { captain_copilot_responses: 500, captain_internal_calls: 500 },
      'crecimiento' => { captain_copilot_responses: 1_500, captain_internal_calls: 1_500 },
      'negocio' => { captain_copilot_responses: 4_000, captain_internal_calls: 4_000 },
      'escala' => { captain_copilot_responses: 10_000, captain_internal_calls: 10_000 }
    }
    dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch('DRY_RUN', nil))

    defaults.each do |slug, values|
      plan = Plan.find_by(slug: slug)
      next unless plan

      if dry_run
        changes = values.select { |attribute, _value| plan.public_send(attribute).nil? }
        puts "Would fill #{slug}: #{changes.inspect}" if changes.any?
        next
      end

      plan.with_lock do
        changes = values.select { |attribute, _value| plan.public_send(attribute).nil? }
        plan.update!(changes) if changes.any?
        puts "Filled #{slug}: #{changes.inspect}" if changes.any?
      end
    end
  end

  desc 'Print every registered plan limit without changing data'
  task limits_report: :environment do
    Plan.ordered.each do |plan|
      puts "#{plan.name} (#{plan.slug})"
      Plan::LIMITS.each do |definition|
        value = plan.limit(definition[:key])
        puts "  #{definition[:key]}: #{value.nil? ? 'unlimited' : value} [#{definition[:enforcement]}]"
      end
    end
  end
end
