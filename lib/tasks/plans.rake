namespace :plans do
  desc 'Seed the real ChatHub pricing plans (Prueba, Inicio, Crecimiento, Negocio, Escala, Developer) as Plan rows'
  task seed: :environment do
    common = {
      addon_agent_price: 18,
      addon_bot_price: 35,
      credit_unit_price: 0.025
    }

    plans = [
      {
        name: 'Prueba', slug: 'prueba', description: 'Plan de prueba gratuito, 15 dias.',
        monthly_messages: 200, storage_mb: 1, max_documents: 1, max_captain_assistants: 1, max_human_agents: 1,
        max_inboxes: 1, max_emails_per_day: 50,
        price_monthly: 0, price_yearly: 0, trial_days: 15, trial_messages: 200, display_order: 0,
        is_default_trial: true
      },
      {
        name: 'Inicio', slug: 'inicio', description: 'Para equipos que estan arrancando con IA.',
        monthly_messages: 1_000, storage_mb: 100, max_documents: 100, max_captain_assistants: 1, max_human_agents: 2,
        max_inboxes: 2, max_emails_per_day: 500,
        price_monthly: 79, price_yearly: 79 * 12, trial_days: 0, trial_messages: 0, display_order: 1,
        is_default_trial: false
      },
      {
        name: 'Crecimiento', slug: 'crecimiento', description: 'El mas elegido. Precio regular USD 149, promocional USD 119.',
        monthly_messages: 3_000, storage_mb: 250, max_documents: 250, max_captain_assistants: 3, max_human_agents: 5,
        max_inboxes: 5, max_emails_per_day: 2_000,
        price_monthly: 119, price_yearly: 119 * 12, trial_days: 0, trial_messages: 0, display_order: 2,
        is_default_trial: false
      },
      {
        name: 'Negocio', slug: 'negocio', description: 'Para equipos con volumen alto de conversaciones.',
        monthly_messages: 8_000, storage_mb: 1024, max_documents: 1024, max_captain_assistants: 5, max_human_agents: 15,
        max_inboxes: 10, max_emails_per_day: 5_000,
        price_monthly: 299, price_yearly: 299 * 12, trial_days: 0, trial_messages: 0, display_order: 3,
        is_default_trial: false
      },
      {
        name: 'Escala', slug: 'escala', description: 'Para operaciones grandes, multiples equipos.',
        monthly_messages: 20_000, storage_mb: 2048, max_documents: 2048, max_captain_assistants: 15, max_human_agents: 40,
        max_inboxes: 25, max_emails_per_day: 15_000,
        price_monthly: 599, price_yearly: 599 * 12, trial_days: 0, trial_messages: 0, display_order: 4,
        is_default_trial: false
      },
      {
        name: 'Developer', slug: 'developer', description: 'BYOK (trae tu propia llave de IA), sin cupo de mensajes incluidos.',
        monthly_messages: 0, storage_mb: 100, max_documents: 100, max_captain_assistants: 3, max_human_agents: 5,
        max_inboxes: 3, max_emails_per_day: 1_000,
        price_monthly: 49, price_yearly: 49 * 12, trial_days: 0, trial_messages: 0, display_order: 5,
        is_default_trial: false
      }
    ]

    plans.each do |attrs|
      plan = Plan.find_or_initialize_by(slug: attrs[:slug])
      was_new = plan.new_record?
      plan.assign_attributes(common.merge(attrs).merge(is_active: true, is_public: true))
      plan.save!
      puts "#{was_new ? 'Created' : 'Updated'}: #{plan.name} (#{plan.slug})"
    end
  end
end
