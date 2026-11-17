export const buildCaptainMenu = ({ isAdmin, t, accountScopedRoute }) => {
  const children = [
    {
      name: 'Overview',
      label: t('SIDEBAR.CAPTAIN_OVERVIEW'),
      activeOn: ['captain_assistants_overview_index'],
      to: accountScopedRoute('captain_assistants_index', {
        navigationPath: 'captain_assistants_overview_index',
      }),
    },
    {
      name: 'FAQs',
      label: t('SIDEBAR.CAPTAIN_RESPONSES'),
      activeOn: [
        'captain_assistants_responses_index',
        'captain_assistants_faq_suggestions',
      ],
      to: accountScopedRoute('captain_assistants_index', {
        navigationPath: 'captain_assistants_responses_index',
      }),
    },
    {
      name: 'Documents',
      label: t('SIDEBAR.CAPTAIN_DOCUMENTS'),
      activeOn: ['captain_assistants_documents_index'],
      to: accountScopedRoute('captain_assistants_index', {
        navigationPath: 'captain_assistants_documents_index',
      }),
    },
  ];

  if (isAdmin) {
    children.push({
      name: 'Scenarios',
      label: t('SIDEBAR.CAPTAIN_SCENARIOS'),
      activeOn: ['captain_assistants_scenarios_index'],
      to: accountScopedRoute('captain_assistants_index', {
        navigationPath: 'captain_assistants_scenarios_index',
      }),
    });
  }

  children.push(
    {
      name: 'Playground',
      label: t('SIDEBAR.CAPTAIN_PLAYGROUND'),
      activeOn: ['captain_assistants_playground_index'],
      to: accountScopedRoute('captain_assistants_index', {
        navigationPath: 'captain_assistants_playground_index',
      }),
    },
    {
      name: 'Inboxes',
      label: t('SIDEBAR.CAPTAIN_INBOXES'),
      activeOn: ['captain_assistants_inboxes_index'],
      to: accountScopedRoute('captain_assistants_index', {
        navigationPath: 'captain_assistants_inboxes_index',
      }),
    },
    {
      name: 'Tools',
      label: t('SIDEBAR.CAPTAIN_TOOLS'),
      activeOn: ['captain_tools_index'],
      to: accountScopedRoute('captain_assistants_index', {
        navigationPath: 'captain_tools_index',
      }),
    }
  );

  if (isAdmin) {
    children.push({
      name: 'Settings',
      label: t('SIDEBAR.CAPTAIN_SETTINGS'),
      activeOn: [
        'captain_assistants_settings_index',
        'captain_assistants_settings_system_index',
        'captain_assistants_settings_audience_index',
        'captain_assistants_settings_schedule_index',
        'captain_assistants_settings_appointments_index',
        'captain_assistants_settings_followup_index',
        'captain_assistants_settings_messaging_index',
        'captain_assistants_guidelines_index',
        'captain_assistants_guardrails_index',
      ],
      to: accountScopedRoute('captain_assistants_index', {
        navigationPath: 'captain_assistants_settings_index',
      }),
    });
  }

  return children;
};
