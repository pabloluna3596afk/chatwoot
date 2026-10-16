import { calendarEventTooltip, isUpcomingEvent } from '../calendarTime';

it('never treats either form of cancellation as an upcoming appointment', () => {
  const event = {
    start: '2030-01-15T10:00:00-05:00',
    end: '2030-01-15T10:30:00-05:00',
  };
  const now = new Date('2030-01-14T00:00:00Z').getTime();
  expect(isUpcomingEvent(event, now)).toBe(true);
  expect(isUpcomingEvent({ ...event, deleted: true }, now)).toBe(false);
  expect(
    isUpcomingEvent({ ...event, appointment_status: 'cancelled' }, now)
  ).toBe(false);
});

it('localizes tooltip status and lets cancellation override confirmation', () => {
  const event = {
    summary: 'Cita · Ana Pérez',
    start: '2030-01-15T10:00:00-05:00',
    end: '2030-01-15T10:30:00-05:00',
    appointment_status: 'confirmed',
    deleted: true,
  };
  const t = key =>
    ({ 'SIDEBAR.CALENDAR_PAGE.STATUS.CANCELLED': 'Cancelada' })[key];
  expect(calendarEventTooltip(event, t)).toBe(
    'Cita · Ana Pérez\n10:00 – 10:30\nCancelada'
  );
});
