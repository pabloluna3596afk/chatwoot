import { flushPromises, shallowMount } from '@vue/test-utils';
import NextAppointmentCard from '../NextAppointmentCard.vue';

const { getContactEvents } = vi.hoisted(() => ({ getContactEvents: vi.fn() }));

vi.mock('dashboard/api/integrations/calendar', () => ({
  default: { getContactEvents },
}));

vi.mock('vue-i18n', () => ({
  useI18n: () => ({ t: key => key, locale: { value: 'es' } }),
}));

const event = (id, start, extra = {}) => ({
  id,
  summary: `Cita ${id}`,
  start,
  end: start,
  deleted: false,
  appointment_status: 'confirmed',
  creator: { type: 'captain', name: 'Aurora' },
  ...extra,
});

const future = days => new Date(Date.now() + days * 86400000).toISOString();

const mountCard = async () => {
  const wrapper = shallowMount(NextAppointmentCard, {
    props: { contactId: 7 },
  });
  await flushPromises();
  return wrapper;
};

describe('NextAppointmentCard', () => {
  beforeEach(() => {
    getContactEvents.mockReset();
  });

  it('pins the next upcoming appointment of the contact', async () => {
    getContactEvents.mockResolvedValue({
      data: {
        payload: [
          event('later', future(9)),
          event('soon', future(2)),
          event('past', future(-3)),
          event('cancelled', future(1), { deleted: true }),
        ],
      },
    });

    const wrapper = await mountCard();

    expect(getContactEvents).toHaveBeenCalledWith(7);
    expect(wrapper.find('[data-testid="next-appointment"]').text()).toContain(
      'Cita soon'
    );
    expect(wrapper.text()).toContain(
      'CONVERSATION_SIDEBAR.CALENDAR.STATUS.CONFIRMED'
    );
  });

  it('shows nothing when there is no upcoming appointment', async () => {
    getContactEvents.mockResolvedValue({
      data: { payload: [event('past', future(-3))] },
    });

    expect(
      (await mountCard()).find('[data-testid="next-appointment"]').exists()
    ).toBe(false);
  });

  it('shows nothing when the request fails', async () => {
    getContactEvents.mockRejectedValue(new Error('boom'));

    expect(
      (await mountCard()).find('[data-testid="next-appointment"]').exists()
    ).toBe(false);
  });

  it('says how the customer answered the invite, and confirms what Captain booked by chat', async () => {
    getContactEvents.mockResolvedValue({
      data: {
        payload: [
          event('soon', future(2), {
            booking_source: 'ai',
            invitation_status: 'needs_action',
          }),
        ],
      },
    });

    const wrapper = await mountCard();

    expect(wrapper.text()).toContain(
      'CONVERSATION_SIDEBAR.CALENDAR.STATUS.CONFIRMED_CHAT'
    );
    expect(
      wrapper.get('[data-testid="next-appointment-invitation"]').text()
    ).toBe('CONVERSATION_SIDEBAR.CALENDAR.INVITATION.NEEDS_ACTION');
  });
});
