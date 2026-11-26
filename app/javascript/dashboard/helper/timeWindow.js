// Value of the automation condition `message_time_window`: "HH:MM-HH:MM" with an optional
// "|day,day" suffix, e.g. "18:00-08:00" or "09:00-13:00|mon,tue". Mirrors
// AutomationRules::TimeWindow on the server.
export const TIME_WINDOW_DAYS = [
  'sun',
  'mon',
  'tue',
  'wed',
  'thu',
  'fri',
  'sat',
];

const FORMAT =
  /^((?:[01]\d|2[0-3]):[0-5]\d)-((?:[01]\d|2[0-3]):[0-5]\d)(?:\|([a-z]{3}(?:,[a-z]{3})*))?$/;

export const parseTimeWindow = value => {
  const match = typeof value === 'string' ? FORMAT.exec(value) : null;
  if (!match) return null;
  const days = match[3] ? match[3].split(',') : [];
  if (days.some(day => !TIME_WINDOW_DAYS.includes(day))) return null;
  if (new Set(days).size !== days.length) return null;
  if (match[1] === match[2]) return null;
  return { from: match[1], to: match[2], days };
};

// Returns '' while the window is incomplete so the form treats it as an empty value.
export const buildTimeWindow = ({ from = '', to = '', days = [] } = {}) => {
  if (!from || !to) return '';
  const ordered = TIME_WINDOW_DAYS.filter(day => days.includes(day));
  return `${from}-${to}${ordered.length ? `|${ordered.join(',')}` : ''}`;
};

export const isValidTimeWindow = value =>
  parseTimeWindow(Array.isArray(value) ? value[0] : value) !== null;

export const summarizeTimeWindow = (value, t) => {
  const parsed = parseTimeWindow(value);
  if (!parsed) return '';
  const selectedDays = TIME_WINDOW_DAYS.filter(day =>
    parsed.days.includes(day)
  );

  let days;
  if (
    selectedDays.length === 0 ||
    selectedDays.length === TIME_WINDOW_DAYS.length
  ) {
    days = t('AUTOMATION.TIME_WINDOW.SUMMARY_ALL_DAYS');
  } else if (selectedDays.join(',') === 'mon,tue,wed,thu,fri') {
    days = t('AUTOMATION.TIME_WINDOW.SUMMARY_WEEKDAYS');
  } else {
    const dayLabels = {
      sun: t('DAYS_OF_WEEK.SUNDAY'),
      mon: t('DAYS_OF_WEEK.MONDAY'),
      tue: t('DAYS_OF_WEEK.TUESDAY'),
      wed: t('DAYS_OF_WEEK.WEDNESDAY'),
      thu: t('DAYS_OF_WEEK.THURSDAY'),
      fri: t('DAYS_OF_WEEK.FRIDAY'),
      sat: t('DAYS_OF_WEEK.SATURDAY'),
    };
    days = selectedDays.map(day => dayLabels[day].slice(0, 3)).join(', ');
  }

  return `${parsed.from}–${parsed.to} · ${days}`;
};
