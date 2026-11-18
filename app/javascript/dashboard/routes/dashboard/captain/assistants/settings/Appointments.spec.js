import { mount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import Appointments from './Appointments.vue';
import CaptainInboxesAPI from 'dashboard/api/captain/inboxes';
import { useAlert } from 'dashboard/composables';

const { updateAssistant, onSaved } = vi.hoisted(() => ({
  updateAssistant: vi.fn(),
  onSaved: vi.fn(),
}));
vi.mock('./useAssistantSettings', () => ({
  useAssistantSettings: () => ({ assistant: ref({ id: 3 }), updateAssistant }),
}));
vi.mock('dashboard/api/captain/inboxes', () => ({
  default: { updateAppointments: vi.fn() },
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));

const mountPage = () =>
  mount(Appointments, {
    global: {
      stubs: {
        SettingsPageLayout: { template: '<div><slot /></div>' },
        AssistantAppointmentsForm: {
          name: 'AssistantAppointmentsForm',
          template: '<div />',
          emits: ['submit'],
        },
      },
    },
  });
const submit = wrapper =>
  wrapper
    .findComponent({ name: 'AssistantAppointmentsForm' })
    .vm.$emit('submit', {
      config: { appointments: { enabled: true } },
      inboxChanges: [{ inboxId: 10, appointmentsEnabled: false }],
      onSaved,
    });

describe('appointment inbox permissions', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    updateAssistant.mockResolvedValue(true);
    CaptainInboxesAPI.updateAppointments.mockResolvedValue({});
  });

  it('saves the form before inbox permissions and acknowledges them after success', async () => {
    const wrapper = mountPage();
    submit(wrapper);
    await flushPromises();
    expect(updateAssistant).toHaveBeenCalledWith({
      config: { appointments: { enabled: true } },
    });
    expect(CaptainInboxesAPI.updateAppointments).toHaveBeenCalledWith({
      assistantId: 3,
      inboxId: 10,
      appointmentsEnabled: false,
    });
    expect(updateAssistant.mock.invocationCallOrder[0]).toBeLessThan(
      CaptainInboxesAPI.updateAppointments.mock.invocationCallOrder[0]
    );
    expect(onSaved).toHaveBeenCalledOnce();
  });

  it('does not save inbox permissions if the form fails', async () => {
    updateAssistant.mockResolvedValue(false);
    submit(mountPage());
    await flushPromises();
    expect(CaptainInboxesAPI.updateAppointments).not.toHaveBeenCalled();
    expect(onSaved).not.toHaveBeenCalled();
  });

  it('keeps the inbox draft if its request fails', async () => {
    CaptainInboxesAPI.updateAppointments.mockRejectedValue(
      new Error('network')
    );
    submit(mountPage());
    await flushPromises();
    expect(onSaved).not.toHaveBeenCalled();
    expect(useAlert).toHaveBeenCalled();
  });
});
