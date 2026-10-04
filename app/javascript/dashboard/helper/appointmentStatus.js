// The status lines of an appointment, as keys of CONVERSATION_SIDEBAR.CALENDAR.STATUS / .INVITATION.

// What the appointment is: what Captain booked after the customer's yes in the chat reads "Confirmada (por chat)".
export const appointmentStatusKey = event => {
  const status = String(event?.appointment_status || '').toLowerCase();
  if (!status || status === 'none') return null;
  if (status === 'confirmed' && event.booking_source === 'ai') {
    return 'CONFIRMED_CHAT';
  }
  return status.toUpperCase();
};

// What the customer answered to the Google invite (needs_action, accepted, declined, tentative), when known.
export const invitationStatusKey = event =>
  event?.invitation_status
    ? String(event.invitation_status).toUpperCase()
    : null;
