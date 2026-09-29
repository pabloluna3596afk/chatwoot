class SuperAdmin::AccountPlanUsagesController < SuperAdmin::ApplicationController
  # Default Administrate CRUD actions are enough here — AccountPlanUsage is
  # configuration/data history, nothing custom to override.
  # Note: This is intentionally read-only in the UI, but the controller
  # still allows all actions for API access if needed.
end