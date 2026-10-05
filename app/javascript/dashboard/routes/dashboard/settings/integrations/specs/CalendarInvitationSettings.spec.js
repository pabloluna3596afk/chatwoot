import { flushPromises, mount } from '@vue/test-utils';
import CalendarInvitationSettings from '../CalendarInvitationSettings.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'es' } }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getInvitation: vi.fn(), updateInvitation: vi.fn() },
}));

const DEFAULT = 'Hola {{primer_nombre}}, te esperamos.\n\nLugar: {{direccion}}';

const mountSettings = async (data = {}) => {
  CalendarAPI.getInvitation.mockResolvedValue({
    data: {
      template: null,
      location: null,
      default_template: DEFAULT,
      max_length: 4000,
      ...data,
    },
  });
  const wrapper = mount(CalendarInvitationSettings, {
    global: { mocks: { $t: key => key } },
  });
  await flushPromises();
  return wrapper;
};

// The text of the invitation is the first textarea of the card, the address the second.
const textarea = wrapper => wrapper.findAll('textarea')[0];
const locationField = wrapper => wrapper.findAll('textarea')[1];

describe('CalendarInvitationSettings', () => {
  beforeEach(() => {
    CalendarAPI.getInvitation.mockReset();
    CalendarAPI.updateInvitation.mockReset();
  });

  it('starts from the default text while the account has none, and says so', async () => {
    const wrapper = await mountSettings();

    expect(textarea(wrapper).element.value).toBe(DEFAULT);
    expect(wrapper.text()).toContain('CALENDAR_INVITATION.USING_DEFAULT');
    expect(
      wrapper.get('[data-testid="invitation-save"]').attributes('disabled')
    ).toBeDefined();
  });

  it('shows the text the account wrote and a preview with sample data', async () => {
    const wrapper = await mountSettings({
      template: 'Te esperamos {{primer_nombre}} con {{agente}}',
      location: 'Av. Sol 1',
    });

    expect(textarea(wrapper).element.value).toBe(
      'Te esperamos {{primer_nombre}} con {{agente}}'
    );
    expect(wrapper.get('[data-testid="invitation-preview"]').text()).toBe(
      'Te esperamos Ana con Aurora'
    );
    expect(wrapper.text()).not.toContain('CALENDAR_INVITATION.USING_DEFAULT');
  });

  it('leaves out of the preview the line of an address nobody wrote', async () => {
    const wrapper = await mountSettings();

    expect(wrapper.get('[data-testid="invitation-preview"]').text()).toBe(
      'Hola Ana, te esperamos.'
    );

    await locationField(wrapper).setValue('Av. Sol 1');
    expect(wrapper.get('[data-testid="invitation-preview"]').text()).toContain(
      'Lugar: Av. Sol 1'
    );
  });

  it('saves what was written, and the address, then shows what the server kept', async () => {
    CalendarAPI.updateInvitation.mockResolvedValue({
      data: {
        template: 'Nuevo texto',
        location: '',
        default_template: DEFAULT,
        max_length: 4000,
      },
    });
    const wrapper = await mountSettings();

    await textarea(wrapper).setValue('Nuevo texto');
    await wrapper.get('[data-testid="invitation-save"]').trigger('click');
    await flushPromises();

    expect(CalendarAPI.updateInvitation).toHaveBeenCalledWith({
      template: 'Nuevo texto',
      location: '',
    });
  });

  it('saves the default text as nothing, so the account follows the default', async () => {
    CalendarAPI.updateInvitation.mockResolvedValue({
      data: { template: null, location: 'Aquí', default_template: DEFAULT },
    });
    const wrapper = await mountSettings({ template: 'Otro texto' });

    await wrapper.get('[data-testid="invitation-restore"]').trigger('click');
    await wrapper.get('[data-testid="invitation-save"]').trigger('click');
    await flushPromises();

    expect(CalendarAPI.updateInvitation).toHaveBeenCalledWith({
      template: '',
      location: '',
    });
  });

  it('does not let a text with a variable that does not exist be saved', async () => {
    const wrapper = await mountSettings();

    await textarea(wrapper).setValue('Hola {{nobre}}');

    expect(wrapper.text()).toContain('CALENDAR_INVITATION.UNKNOWN');
    expect(
      wrapper.get('[data-testid="invitation-save"]').attributes('disabled')
    ).toBeDefined();
  });
});
