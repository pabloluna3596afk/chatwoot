import {
  appointmentStatusKey,
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
