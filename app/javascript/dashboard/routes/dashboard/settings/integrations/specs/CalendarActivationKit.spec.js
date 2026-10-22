import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import CalendarActivationKit from '../CalendarActivationKit.vue';
import CalendarAPI from 'dashboard/api/integrations/calendar';
import { useAlert } from 'dashboard/composables';
import en from 'dashboard/i18n/locale/en/calendarActivationKit.json';
import es from 'dashboard/i18n/locale/es/calendarActivationKit.json';

const { isAdmin } = vi.hoisted(() => ({ isAdmin: { value: true } }));

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ accountScopedRoute: name => ({ name }) }),
}));
vi.mock('dashboard/composables/useAdmin', async () => {
  const { computed } = await import('vue');
  return { useAdmin: () => ({ isAdmin: computed(() => isAdmin.value) }) };
});
vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getActivationKit: vi.fn(), applyActivationKit: vi.fn() },
}));

const kitWith = (inboxes, extra = {}) => ({
  attributes: { enabled_keys: ['ultima_cita', 'total_citas'] },
  template: {
    name: 'cita_confirmacion',
    language: 'es',
    category: 'UTILITY',
    body: 'Hola {{nombre}}, tu cita quedó agendada.',
    buttons: ['Confirmar', 'Reagendar', 'Cancelar'],
  },
  inboxes,
  ...extra,
});
const inbox = (id, status, rejectedReason = null) => ({
  id,
  name: `WhatsApp ${id}`,
  status,
  rejected_reason: rejectedReason,
});

const mountKit = async (data, locale = 'es') => {
  CalendarAPI.getActivationKit.mockResolvedValue({ data });
  const wrapper = mount(CalendarActivationKit, {
    global: {
      plugins: [
        createI18n({
          legacy: false,
          locale,
          messages: { en, es },
        }),
      ],
      stubs: { 'router-link': { template: '<a><slot /></a>' } },
    },
  });
  await flushPromises();
  return wrapper;
};

describe('CalendarActivationKit', () => {
  beforeEach(() => {
    vi.clearAllMocks();
    isAdmin.value = true;
  });

  it('shows the attributes, the template and the status of each WhatsApp inbox', async () => {
    const wrapper = await mountKit(
      kitWith([
        inbox(1, 'missing'),
        inbox(2, 'pending'),
        inbox(3, 'approved'),
        inbox(4, 'rejected', 'INVALID_FORMAT'),
      ])
    );

    expect(
      wrapper.get('[data-testid="activation-kit-attributes"]').text()
    ).toContain('2 de 4 activos');
    expect(
      wrapper.get('[data-testid="activation-kit-preview"]').text()
    ).toContain('Hola {{nombre}}');
    expect(wrapper.get('[data-testid="activation-kit-status-1"]').text()).toBe(
      'Sin enviar'
    );
    expect(wrapper.get('[data-testid="activation-kit-status-2"]').text()).toBe(
      'Pendiente'
    );
    expect(wrapper.get('[data-testid="activation-kit-status-3"]').text()).toBe(
      'Aprobada'
    );
    expect(wrapper.get('[data-testid="activation-kit-status-4"]').text()).toBe(
      'Rechazada'
    );
    expect(
      wrapper.get('[data-testid="activation-kit-inbox-4"]').text()
    ).toContain('Motivo de Meta: INVALID_FORMAT');
  });

  it('only lets an inbox without a pending or approved template be marked', async () => {
    const wrapper = await mountKit(
      kitWith([inbox(1, 'missing'), inbox(2, 'pending'), inbox(3, 'approved')])
    );

    expect(
      wrapper
        .get('[data-testid="activation-kit-check-1"] input')
        .attributes('disabled')
    ).toBeUndefined();
    expect(
      wrapper
        .get('[data-testid="activation-kit-check-2"] input')
        .attributes('disabled')
    ).toBeDefined();
    expect(
      wrapper
        .get('[data-testid="activation-kit-check-3"] input')
        .attributes('disabled')
    ).toBeDefined();
  });

  it('sends the marked inboxes to Meta and shows the new status', async () => {
    const wrapper = await mountKit(
      kitWith([inbox(1, 'missing'), inbox(2, 'missing')])
    );
    CalendarAPI.applyActivationKit.mockResolvedValue({
      data: kitWith([inbox(1, 'pending'), inbox(2, 'missing')], {
        results: { 1: { status: 'pending' } },
      }),
    });

    expect(
      wrapper.get('[data-testid="activation-kit-send"]').attributes('disabled')
    ).toBeDefined();
    await wrapper
      .get('[data-testid="activation-kit-check-1"] input')
      .setValue(true);
    await wrapper.get('[data-testid="activation-kit-send"]').trigger('click');
    await flushPromises();

    expect(CalendarAPI.applyActivationKit).toHaveBeenCalledWith([1]);
    expect(wrapper.get('[data-testid="activation-kit-status-1"]').text()).toBe(
      'Pendiente'
    );
    expect(useAlert).toHaveBeenCalledWith(es.CALENDAR_ACTIVATION_KIT.SENT);
  });

  it('shows what Meta answered when an inbox could not be sent', async () => {
    const wrapper = await mountKit(kitWith([inbox(1, 'missing')]));
    CalendarAPI.applyActivationKit.mockResolvedValue({
      data: kitWith([inbox(1, 'missing')], {
        results: {
          1: {
            status: 'error',
            code: 'permission_denied',
            detail: 'no access',
          },
        },
      }),
    });

    await wrapper
      .get('[data-testid="activation-kit-check-1"] input')
      .setValue(true);
    await wrapper.get('[data-testid="activation-kit-send"]').trigger('click');
    await flushPromises();

    expect(wrapper.get('[data-testid="activation-kit-status-1"]').text()).toBe(
      'Error'
    );
    expect(
      wrapper.get('[data-testid="activation-kit-inbox-1"]').text()
    ).toContain(es.CALENDAR_ACTIVATION_KIT.ERRORS.permission_denied);
    expect(useAlert).toHaveBeenCalledWith(
      es.CALENDAR_ACTIVATION_KIT.SENT_WITH_ERRORS
    );
  });

  it('resends a rejected template from its own row', async () => {
    const wrapper = await mountKit(
      kitWith([inbox(4, 'rejected', 'INVALID_FORMAT')])
    );
    CalendarAPI.applyActivationKit.mockResolvedValue({
      data: kitWith([inbox(4, 'pending')], {
        results: { 4: { status: 'pending' } },
      }),
    });

    await wrapper
      .get('[data-testid="activation-kit-resend-4"]')
      .trigger('click');
    await flushPromises();

    expect(CalendarAPI.applyActivationKit).toHaveBeenCalledWith([4]);
    expect(wrapper.get('[data-testid="activation-kit-status-4"]').text()).toBe(
      'Pendiente'
    );
  });

  it('asks to create an inbox when the account has no WhatsApp Cloud inbox', async () => {
    const wrapper = await mountKit(kitWith([]));

    expect(
      wrapper.get('[data-testid="activation-kit-no-inbox"]').text()
    ).toContain(es.CALENDAR_ACTIVATION_KIT.NO_INBOX);
    expect(wrapper.find('[data-testid="activation-kit-send"]').exists()).toBe(
      false
    );
  });

  it('keeps the actions for administrators only', async () => {
    isAdmin.value = false;
    const wrapper = await mountKit(
      kitWith([inbox(1, 'missing'), inbox(4, 'rejected')])
    );

    expect(wrapper.find('[data-testid="activation-kit-send"]').exists()).toBe(
      false
    );
    expect(
      wrapper.find('[data-testid="activation-kit-resend-4"]').exists()
    ).toBe(false);
    expect(
      wrapper
        .get('[data-testid="activation-kit-check-1"] input')
        .attributes('disabled')
    ).toBeDefined();
    expect(wrapper.find('[data-testid="activation-kit-reload"]').exists()).toBe(
      true
    );
  });

  it('shows a retry when the kit cannot be loaded', async () => {
    CalendarAPI.getActivationKit.mockRejectedValue(new Error('boom'));
    const wrapper = mount(CalendarActivationKit, {
      global: {
        plugins: [
          createI18n({ legacy: false, locale: 'es', messages: { en, es } }),
        ],
        stubs: { 'router-link': true },
      },
    });
    await flushPromises();

    expect(wrapper.get('[role="alert"]').text()).toContain(
      es.CALENDAR_ACTIVATION_KIT.LOAD_ERROR
    );
    expect(useAlert).toHaveBeenCalledWith(
      es.CALENDAR_ACTIVATION_KIT.LOAD_ERROR
    );
  });

  it('has the same keys in Spanish and English', () => {
    const keys = object =>
      Object.entries(object).flatMap(([key, value]) =>
        typeof value === 'object'
          ? keys(value).map(item => `${key}.${item}`)
          : [key]
      );

    expect(keys(en).sort()).toEqual(keys(es).sort());
  });

  it('previews the quick-reply buttons of the template', async () => {
    const wrapper = await mountKit(kitWith([inbox(1, 'missing')]));

    expect(
      wrapper.get('[data-testid="activation-kit-buttons"]').text()
    ).toContain('Reagendar');
  });
});
