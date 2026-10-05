import { flushPromises, shallowMount } from '@vue/test-utils';
import EventModal from '../EventModal.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'es' } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/store', () => ({
  useMapGetter: () => ({ value: { name: 'Pablo' } }),
}));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: { name: 'Clínica Sol' } } }),
}));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: {
    lockEvent: vi.fn().mockResolvedValue({}),
    unlockEvent: vi.fn(),
    getInvitation: vi.fn(),
    createEvent: vi.fn(),
    updateEvent: vi.fn(),
  },
}));

const DialogStub = {
  template: '<div><slot /></div>',
  emits: ['confirm', 'close'],
  methods: { open() {}, close() {} },
};

const mountModal = () =>
  shallowMount(EventModal, {
    props: { connections: [{ id: 1, email: 'a@b.c' }], calendars: [] },
    global: {
      mocks: { $t: key => key },
      stubs: { Dialog: DialogStub, TabBar: true },
    },
  });

const newAppointment = {
  defaults: {
    connectionId: '1',
    calendarId: 'cal-1',
    startIso: '2030-01-15T10:00:00-05:00',
    contactId: 5,
    contactName: 'ana pérez',
  },
};

const existing = (extra = {}) => ({
  event: {
    id: 'e1',
    summary: 'Consulta',
    start: '2030-01-15T10:00:00-05:00',
    end: '2030-01-15T10:30:00-05:00',
    connection_id: 1,
    calendar_id: 'cal-1',
    contact: { id: 5, name: 'ana pérez' },
    ...extra,
  },
  defaults: {},
});

const preview = wrapper =>
  wrapper.get('[data-testid="invitation-preview"]').text();
const save = async wrapper => {
  wrapper.findComponent(DialogStub).vm.$emit('confirm');
  await flushPromises();
};
const textarea = wrapper => wrapper.findComponent({ name: 'TextArea' });

describe('EventModal invitation text', () => {
  beforeEach(() => {
    CalendarAPI.getInvitation.mockReset();
    CalendarAPI.createEvent.mockReset();
    CalendarAPI.updateEvent.mockReset();
    CalendarAPI.getInvitation.mockResolvedValue({
      data: {
        template: null,
        default_template:
          'Hola {{primer_nombre}}, tu cita con {{agente}} es el {{fecha}} a las {{hora}}.\nLugar: {{direccion}}',
        location: '',
      },
    });
    CalendarAPI.createEvent.mockResolvedValue({ data: { payload: {} } });
    CalendarAPI.updateEvent.mockResolvedValue({ data: { payload: {} } });
  });

  it("shows the account's text with the values of this appointment", async () => {
    const wrapper = mountModal();
    await wrapper.vm.open(newAppointment);
    await flushPromises();

    expect(preview(wrapper)).toBe(
      'Hola Ana, tu cita con Pablo es el martes 15 de enero a las 10:00.'
    );
  });

  it('follows the time when it changes, and leaves out the address nobody wrote', async () => {
    const wrapper = mountModal();
    await wrapper.vm.open(newAppointment);
    await flushPromises();

    wrapper.vm.$.setupState.time = '11:30';
    wrapper.vm.$.setupState.date = '2030-01-16';
    await flushPromises();

    expect(preview(wrapper)).toContain('miércoles 16 de enero a las 11:30');
    expect(preview(wrapper)).not.toContain('Lugar');
  });

  it('sends nothing about the text while the appointment keeps the account text', async () => {
    const wrapper = mountModal();
    await wrapper.vm.open({
      ...newAppointment,
      defaults: { ...newAppointment.defaults },
    });
    await flushPromises();
    wrapper.vm.$.setupState.summary = 'Consulta';
    await flushPromises();

    await save(wrapper);

    expect(CalendarAPI.createEvent).toHaveBeenCalledTimes(1);
    expect(CalendarAPI.createEvent.mock.calls[0][0]).not.toHaveProperty(
      'description'
    );
  });

  it('sends the text the agent wrote, with its variables, and shows it filled in', async () => {
    const wrapper = mountModal();
    await wrapper.vm.open(newAppointment);
    await flushPromises();
    wrapper.vm.$.setupState.summary = 'Consulta';

    textarea(wrapper).vm.$emit(
      'update:modelValue',
      ' Trae tu cédula, {{nombre}} '
    );
    await flushPromises();
    expect(preview(wrapper)).toBe('Trae tu cédula, ana pérez');

    await save(wrapper);
    expect(CalendarAPI.createEvent.mock.calls[0][0]).toMatchObject({
      description: 'Trae tu cédula, {{nombre}}',
    });
  });

  it('shows the text an appointment already has and keeps sending it', async () => {
    const wrapper = mountModal();
    await wrapper.vm.open(
      existing({ invitation_text: 'Texto propio {{hora}}' })
    );
    await flushPromises();

    expect(textarea(wrapper).props('modelValue')).toBe('Texto propio {{hora}}');
    expect(preview(wrapper)).toBe('Texto propio 10:00');

    await save(wrapper);
    expect(CalendarAPI.updateEvent.mock.calls[0][1]).toMatchObject({
      description: 'Texto propio {{hora}}',
    });
  });

  it("goes back to the account's text and clears the one it had", async () => {
    const wrapper = mountModal();
    await wrapper.vm.open(existing({ invitation_text: 'Texto propio' }));
    await flushPromises();

    await wrapper
      .get('[data-testid="invitation-use-account"]')
      .trigger('click');
    expect(preview(wrapper)).toContain('Hola Ana');

    await save(wrapper);
    expect(CalendarAPI.updateEvent.mock.calls[0][1]).toMatchObject({
      description: '',
    });
  });

  it('does not send the text of an existing appointment that never had its own', async () => {
    const wrapper = mountModal();
    await wrapper.vm.open(existing());
    await flushPromises();

    await save(wrapper);

    expect(CalendarAPI.updateEvent.mock.calls[0][1]).not.toHaveProperty(
      'description'
    );
  });
});
