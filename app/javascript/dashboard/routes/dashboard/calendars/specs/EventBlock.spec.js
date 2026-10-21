import { vi } from 'vitest';
vi.mock('dashboard/composables/useAccount', () => ({
  useAccount: () => ({ currentAccount: { value: {} } }),
}));

import { mount } from '@vue/test-utils';
import EventBlock from '../EventBlock.vue';

it('keeps the appointment title and time visible and emits selection for cancelled events', async () => {
  const event = {
    id: 'a',
    summary: 'Consultation',
    start: '2030-01-15T10:00:00-05:00',
    end: '2030-01-15T10:30:00-05:00',
    timeLabel: '10:00',
    appointment_status: 'cancelled',
  };
  const wrapper = mount(EventBlock, { props: { event } });
  expect(wrapper.text()).toContain('Consultation');
  expect(wrapper.text()).toContain('10:00');
  expect(wrapper.classes()).toContain('bg-n-ruby-3');
  expect(wrapper.get('.line-through').text()).toBe('Consultation');
  expect(wrapper.attributes('title')).toBe(
    'Consultation\n10:00 – 10:30\nSIDEBAR.CALENDAR_PAGE.STATUS.CANCELLED'
  );
  await wrapper.trigger('click');
  expect(wrapper.emitted('select')[0]).toEqual([event]);
});

it('uses the confirmation palette for confirmed events', () => {
  const wrapper = mount(EventBlock, {
    props: {
      event: {
        summary: 'Consultation',
        start: '2030-01-15T10:00:00-05:00',
        end: '2030-01-15T10:30:00-05:00',
        appointment_status: 'confirmed',
      },
    },
  });
  expect(wrapper.classes()).toContain('bg-n-teal-3');
  expect(wrapper.find('.line-through').exists()).toBe(false);
});

it.each(['Cita · Ana Pérez', 'Appointment · Ana Pérez', 'Reunión de equipo'])(
  'prioritizes the name in a narrow lane without changing the full title %s',
  summary => {
    const event = {
      summary,
      start: '2030-01-15T11:30:00-05:00',
      end: '2030-01-15T12:00:00-05:00',
      timeLabel: '11:30',
      appointment_status: 'confirmed',
    };
    const wrapper = mount(EventBlock, { props: { event, compact: true } });
    expect(wrapper.text()).toBe(
      summary === 'Reunión de equipo' ? summary : 'Ana Pérez'
    );
    expect(wrapper.get('.truncate').text()).toBe(wrapper.text());
    expect(wrapper.text()).not.toContain('11:30');
    expect(wrapper.attributes('title')).toBe(
      `${summary}\n11:30 – 12:00\nSIDEBAR.CALENDAR_PAGE.STATUS.CONFIRMED`
    );
    expect(event.summary).toBe(summary);
  }
);
