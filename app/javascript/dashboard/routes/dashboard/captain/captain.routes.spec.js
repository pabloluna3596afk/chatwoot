import { routes } from './captain.routes';

vi.mock('../../../helper/URLHelper', () => ({
  frontendURL: path => path,
}));
vi.mock('./pages/CaptainPageRouteView.vue', () => ({ default: {} }));
vi.mock('./pages/AssistantsIndexPage.vue', () => ({ default: {} }));
vi.mock('./assistants/Index.vue', () => ({ default: {} }));
vi.mock('./assistants/overview/Index.vue', () => ({ default: {} }));
vi.mock('./assistants/settings/Index.vue', () => ({ default: {} }));
vi.mock('./assistants/settings/System.vue', () => ({ default: {} }));
vi.mock('./assistants/settings/Audience.vue', () => ({ default: {} }));
vi.mock('./assistants/settings/Schedule.vue', () => ({ default: {} }));
vi.mock('./assistants/settings/Appointments.vue', () => ({ default: {} }));
vi.mock('./assistants/settings/Followup.vue', () => ({ default: {} }));
vi.mock('./assistants/settings/Messaging.vue', () => ({ default: {} }));
vi.mock('./assistants/inboxes/Index.vue', () => ({ default: {} }));
vi.mock('./assistants/playground/Index.vue', () => ({ default: {} }));
vi.mock('./assistants/guardrails/Index.vue', () => ({ default: {} }));
vi.mock('./assistants/guidelines/Index.vue', () => ({ default: {} }));
vi.mock('./assistants/scenarios/Index.vue', () => ({ default: {} }));
vi.mock('./documents/Index.vue', () => ({ default: {} }));
vi.mock('./responses/Index.vue', () => ({ default: {} }));
vi.mock('./responses/FaqSuggestions.vue', () => ({ default: {} }));
vi.mock('./tools/Index.vue', () => ({ default: {} }));

const assistantRoutes = routes[0].children;
const routeByName = name => assistantRoutes.find(route => route.name === name);

describe('Captain route permissions', () => {
  it.each([
    'captain_assistants_settings_index',
    'captain_assistants_settings_system_index',
    'captain_assistants_settings_audience_index',
    'captain_assistants_settings_schedule_index',
    'captain_assistants_settings_appointments_index',
    'captain_assistants_settings_followup_index',
    'captain_assistants_settings_messaging_index',
    'captain_assistants_guardrails_index',
    'captain_assistants_guidelines_index',
    'captain_assistants_scenarios_index',
  ])('restricts %s to administrators', name => {
    expect(routeByName(name).meta.permissions).toEqual(['administrator']);
  });

  it.each([
    'captain_assistants_index',
    'captain_assistants_inboxes_index',
    'captain_tools_index',
    'captain_assistants_overview_index',
    'captain_assistants_responses_index',
    'captain_assistants_documents_index',
    'captain_assistants_playground_index',
  ])('keeps %s open to administrators and agents', name => {
    expect(routeByName(name).meta.permissions).toEqual([
      'administrator',
      'agent',
    ]);
  });

  it('redirects the old paid messages URL to messaging with its params and query', () => {
    const legacy = assistantRoutes.find(route =>
      route.path.endsWith('/settings/paid-messages')
    );
    const params = { accountId: '1', assistantId: '2' };
    const query = { tab: 'saved' };

    expect(legacy.redirect({ params, query })).toEqual({
      name: 'captain_assistants_settings_messaging_index',
      params,
      query,
    });
  });
});
