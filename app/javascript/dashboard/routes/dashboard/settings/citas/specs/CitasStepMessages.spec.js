import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { createMemoryHistory, createRouter } from 'vue-router';
import CitasStepMessages from '../CitasStepMessages.vue';
import { buildTemplateState } from '../useCitasPanel';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import activationEn from 'dashboard/i18n/locale/en/calendarActivationKit.json';
import invitationsEn from 'dashboard/i18n/locale/en/calendarInvitation.json';
import settingsEn from 'dashboard/i18n/locale/en/settings.json';

vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    getActivationKit: vi.fn(),
    updateReminderEnabled: vi.fn(),
    prepareTemplateDrafts: vi.fn(),
    submitTemplateDrafts: vi.fn(),
  },
}));

const backendState = state => {
  if (state === 'approved') return 'usable';
  if (state === 'review') return 'pending_approval';
  if (state === 'rejected') return 'incompatible';
  return 'not_submitted';
};
const destination = state => ({
  waba_id: 'one',
  state: backendState(state),
  reason: state === 'rejected' ? 'rejected' : undefined,
  submission:
    state === 'rejected'
      ? { remote_status: 'REJECTED', remote_reason: 'Too long' }
      : undefined,
  channels: [{ id: 1, name: 'Sales', phone_number: '+100' }],
});
const destinationFor = (waba_id, state) => ({
  ...destination(state),
  waba_id,
});
const data = {
  effective_language: 'en',
  results: {
    confirmation: {
      draft_exists: true,
      destinations: [destination('approved')],
    },
    cancellation: {
      draft_exists: true,
      destinations: [destination('rejected')],
    },
    reminder: { draft_exists: true, destinations: [destination('review')] },
  },
};
const SubmissionDialogStub = {
  name: 'TemplateSubmissionDialog',
  props: ['accounts', 'templates', 'isLoading', 'error', 'feedback'],
  emits: ['submit', 'close'],
  setup(_, { expose }) {
    expose({ setAccount: vi.fn(), close: vi.fn(), open: vi.fn() });
    return {};
  },
  template: `
    <div data-testid="submission-dialog">
      <button data-testid="emit-submission" @click="$emit('submit', { functions: ['confirmation'], waba_ids: ['a'] })"></button>
      <p v-if="feedback" role="status">{{ feedback }}</p>
      <p v-if="error" role="alert"></p>
    </div>
  `,
};
const render = ({ templateData = data, refresh = vi.fn() } = {}) =>
  mount(CitasStepMessages, {
    props: {
      connected: true,
      expanded: true,
      disabled: false,
      templateData,
      templateState: buildTemplateState(templateData),
      loading: false,
      error: false,
      refresh,
    },
    global: {
      plugins: [
        createRouter({
          history: createMemoryHistory(),
          routes: [{ path: '/', component: { template: '<div />' } }],
        }),
        createI18n({
          legacy: false,
          locale: 'en',
          messages: {
            en: { ...activationEn, ...invitationsEn, ...settingsEn },
          },
        }),
      ],
      stubs: {
        Button: {
          props: ['label', 'disabled', 'isLoading'],
          template: '<button :disabled="disabled">{{ label }}</button>',
        },
        Switch: {
          props: ['modelValue', 'disabled', 'ariaLabel'],
          emits: ['update:modelValue'],
          template:
            '<input type="checkbox" :checked="modelValue" :disabled="disabled" :aria-label="ariaLabel" @change="$emit(\'update:modelValue\', $event.target.checked)" />',
        },
        TemplateSubmissionDialog: SubmissionDialogStub,
        TemplatePreviewDrawer: true,
        WhatsAppBubble: true,
      },
    },
  });

describe('CitasStepMessages', () => {
  beforeEach(() => {
    CalendarAPI.getActivationKit.mockResolvedValue({
      data: { reminder_enabled: false },
    });
  });

  it('shows an approval summary, rejected reason and the reminder lock', async () => {
    const wrapper = render();
    await flushPromises();
    expect(wrapper.text()).toContain('1 of 3 approved');
    expect(wrapper.text()).toContain('Rejected: "Too long"');
    expect(wrapper.text()).toContain(
      '24 h reminder · available once the reminder is approved'
    );
    expect(
      wrapper.get('input[type="checkbox"]').attributes('disabled')
    ).toBeDefined();
  });

  it('enables and saves the reminder only after its template is approved', async () => {
    const approvedReminderData = {
      ...data,
      results: {
        ...data.results,
        reminder: {
          draft_exists: true,
          destinations: [destination('approved')],
        },
      },
    };
    const wrapper = render({ templateData: approvedReminderData });
    await flushPromises();

    expect(wrapper.get('input[type="checkbox"]').attributes('disabled')).toBe(
      undefined
    );
    await wrapper.get('input[type="checkbox"]').setValue(true);
    await flushPromises();

    expect(CalendarAPI.updateReminderEnabled).toHaveBeenCalledWith(true);
  });

  it('moves to another account with pending templates after a successful send', async () => {
    const accountData = {
      effective_language: 'en',
      results: Object.fromEntries(
        ['confirmation', 'cancellation', 'reminder'].map(key => [
          key,
          {
            draft_exists: true,
            destinations: [
              destinationFor(
                'a',
                key === 'confirmation' ? 'unsent' : 'approved'
              ),
              destinationFor(
                'b',
                key === 'cancellation' ? 'unsent' : 'approved'
              ),
            ],
          },
        ])
      ),
    };
    const refreshedData = {
      ...accountData,
      results: Object.fromEntries(
        Object.entries(accountData.results).map(([key, result]) => [
          key,
          {
            ...result,
            destinations: result.destinations.map(item => ({
              ...item,
              state:
                item.waba_id === 'a' && key === 'confirmation'
                  ? 'usable'
                  : item.state,
            })),
          },
        ])
      ),
    };
    let wrapper;
    const refresh = vi.fn(async () =>
      wrapper.setProps({
        templateData: refreshedData,
        templateState: buildTemplateState(refreshedData),
      })
    );
    CalendarAPI.submitTemplateDrafts.mockResolvedValue({ data: {} });
    wrapper = render({ templateData: accountData, refresh });
    await flushPromises();

    wrapper.get('[data-testid="emit-submission"]').element.click();
    await flushPromises();

    expect(CalendarAPI.submitTemplateDrafts).toHaveBeenCalledWith({
      functions: ['confirmation'],
      waba_ids: ['a'],
    });
    expect(
      wrapper.findComponent(SubmissionDialogStub).vm.setAccount
    ).toHaveBeenCalledWith('b');
    expect(wrapper.text()).toContain('Choose another account.');
  });

  it('closes after the refresh shows no remaining pending templates', async () => {
    const approvedData = {
      ...data,
      results: Object.fromEntries(
        Object.entries(data.results).map(([key, result]) => [
          key,
          {
            ...result,
            destinations: result.destinations.map(item => ({
              ...item,
              state: 'usable',
              reason: undefined,
              submission: undefined,
            })),
          },
        ])
      ),
    };
    let wrapper;
    const refresh = vi.fn(async () =>
      wrapper.setProps({
        templateData: approvedData,
        templateState: buildTemplateState(approvedData),
      })
    );
    CalendarAPI.submitTemplateDrafts.mockResolvedValue({ data: {} });
    wrapper = render({ refresh });
    await flushPromises();
    await wrapper.get('[data-testid="emit-submission"]').trigger('click');
    await flushPromises();

    expect(
      wrapper.findComponent(SubmissionDialogStub).vm.close
    ).toHaveBeenCalled();
  });

  it('keeps the dialog open and reports partial and network failures', async () => {
    const wrapper = render();
    await flushPromises();
    CalendarAPI.submitTemplateDrafts.mockResolvedValue({
      data: { failed: [{ reason: 'submission_failed' }] },
    });
    await wrapper.get('[data-testid="emit-submission"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[data-testid="submission-dialog"]').exists()).toBe(
      true
    );
    expect(wrapper.get('[role="status"]').text()).toContain('0 of 1 submitted');

    CalendarAPI.submitTemplateDrafts.mockRejectedValue(new Error('offline'));
    await wrapper.get('[data-testid="emit-submission"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('[role="alert"]').exists()).toBe(true);
  });

  it('ignores a second submit while the first request is pending', async () => {
    const wrapper = render();
    await flushPromises();
    let resolveSubmission;
    CalendarAPI.submitTemplateDrafts.mockReturnValue(
      new Promise(resolve => {
        resolveSubmission = resolve;
      })
    );

    await wrapper.get('[data-testid="emit-submission"]').trigger('click');
    await wrapper.get('[data-testid="emit-submission"]').trigger('click');
    expect(CalendarAPI.submitTemplateDrafts).toHaveBeenCalledTimes(1);

    resolveSubmission({ data: {} });
    await flushPromises();
  });
});
