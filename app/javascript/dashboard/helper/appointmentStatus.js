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

// Deletion takes precedence over confirmation, including legacy status-only cancellations.
export const isCancelledEvent = event =>
  Boolean(event?.deleted || event?.appointment_status === 'cancelled');

export const calendarEventStatus = event => {
  if (isCancelledEvent(event)) return 'cancelled';
  return event?.appointment_status || 'none';
};

const STATUS_STYLES = {
  confirmed: {
    surface: 'bg-n-teal-3 text-n-teal-11 hover:bg-n-teal-4',
    dot: 'bg-n-teal-9',
    text: 'text-n-teal-11',
  },
  pending_confirmation: {
    surface: 'bg-n-amber-3 text-n-amber-11 hover:bg-n-amber-4',
    dot: 'bg-n-amber-9',
    text: 'text-n-amber-11',
  },
  cancelled: {
    surface:
      'bg-n-ruby-3 text-n-ruby-11 hover:bg-n-ruby-4 ring-1 ring-inset ring-n-ruby-6',
    dot: 'bg-n-ruby-9',
    text: 'text-n-ruby-11',
  },
  rescheduled: {
    surface: 'bg-n-iris-3 text-n-iris-11 hover:bg-n-iris-4',
    dot: 'bg-n-iris-9',
    text: 'text-n-iris-11',
  },
  none: {
    surface: 'bg-n-slate-3 text-n-slate-11 hover:bg-n-slate-4',
    dot: 'bg-n-slate-9',
    text: 'text-n-slate-11',
  },
};

export const calendarEventStyle = event =>
  STATUS_STYLES[calendarEventStatus(event)] || STATUS_STYLES.none;

export const visibleCalendarEvents = (events, showCancelled) =>
  events.filter(event => showCancelled || !isCancelledEvent(event));

export const CALENDAR_LEGEND_STATUSES = [
  'confirmed',
  'pending_confirmation',
  'rescheduled',
  'none',
  'cancelled',
];
