import {
  appointmentStatusKey,
  calendarEventStyle,
  calendarEventStatus,
  isCancelledEvent,
  visibleCalendarEvents,
  invitationStatusKey,
} from '../appointmentStatus';

describe('appointmentStatusKey', () => {
  it('reads "confirmed by chat" for what Captain booked and the customer confirmed', () => {
    expect(
      appointmentStatusKey({
        appointment_status: 'confirmed',
        booking_source: 'ai',
      })
    ).toBe('CONFIRMED_CHAT');
  });

  it('keeps the plain status for the rest', () => {
    expect(
      appointmentStatusKey({
        appointment_status: 'confirmed',
        booking_source: 'manual',
      })
    ).toBe('CONFIRMED');
    expect(
      appointmentStatusKey({ appointment_status: 'pending_confirmation' })
    ).toBe('PENDING_CONFIRMATION');
    expect(appointmentStatusKey({ appointment_status: 'none' })).toBeNull();
    expect(appointmentStatusKey(undefined)).toBeNull();
  });
});

describe('invitationStatusKey', () => {
  it('is the answer of the customer to the invite, when known', () => {
    expect(invitationStatusKey({ invitation_status: 'needs_action' })).toBe(
      'NEEDS_ACTION'
    );
    expect(invitationStatusKey({ invitation_status: 'accepted' })).toBe(
      'ACCEPTED'
    );
    expect(invitationStatusKey({ invitation_status: null })).toBeNull();
    expect(invitationStatusKey({})).toBeNull();
  });
});

describe('calendar event appearance and visibility', () => {
  it.each([
    ['confirmed', 'bg-n-teal-3'],
    ['pending_confirmation', 'bg-n-amber-3'],
    ['rescheduled', 'bg-n-iris-3'],
    ['none', 'bg-n-slate-3'],
    ['cancelled', 'bg-n-ruby-3'],
  ])('maps %s to the shared palette', (status, background) => {
    expect(
      calendarEventStyle({ appointment_status: status }).surface
    ).toContain(background);
  });

  it('gives cancellation precedence over confirmation and keeps untracked meetings neutral', () => {
    expect(
      calendarEventStatus({ deleted: true, appointment_status: 'confirmed' })
    ).toBe('cancelled');
    expect(calendarEventStyle({}).surface).toContain('bg-n-slate-3');
    expect(
      calendarEventStyle({ appointment_status: 'unknown' }).surface
    ).toContain('bg-n-slate-3');
    expect(isCancelledEvent({ invitation_status: 'declined' })).toBe(false);
  });

  it('toggles both forms of cancellation without mutating the source', () => {
    const events = [
      { id: 'active' },
      { id: 'deleted', deleted: true },
      { id: 'cancelled', appointment_status: 'cancelled' },
    ];
    expect(visibleCalendarEvents(events, false).map(event => event.id)).toEqual(
      ['active']
    );
    expect(visibleCalendarEvents(events, true)).toEqual(events);
    expect(events).toHaveLength(3);
  });
});
