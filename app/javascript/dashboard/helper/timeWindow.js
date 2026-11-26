// Value of `message_time_window`: "HH:MM-HH:MM" with an optional
// "|day,day" suffix. No suffix means every day.
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
  return { from: match[1], to: match[2], days };
};

export const getTimeWindowState = ({ from = '', to = '' } = {}) => {
  if (!from || !to) return 'empty';
  if (from === to) return 'same';
  return 'valid';
};

export const buildTimeWindow = ({ from = '', to = '', days = [] } = {}) => {
  if (getTimeWindowState({ from, to }) !== 'valid') return '';
  const ordered = TIME_WINDOW_DAYS.filter(day => days.includes(day));
  let daySuffix = '';
  if (ordered.length && ordered.length !== TIME_WINDOW_DAYS.length) {
    daySuffix = `|${ordered.join(',')}`;
  }
  return `${from}-${to}${daySuffix}`;
};

export const isValidTimeWindow = value => {
  const parsed = parseTimeWindow(Array.isArray(value) ? value[0] : value);
  return parsed !== null && getTimeWindowState(parsed) === 'valid';
};

const summarizeDays = (selectedDays, t) => {
  if (
    selectedDays.length === 0 ||
    selectedDays.length === TIME_WINDOW_DAYS.length
  ) {
    return t('AUTOMATION.TIME_WINDOW.SUMMARY_ALL_DAYS');
  }
  if (selectedDays.join(',') === 'mon,tue,wed,thu,fri') {
    return t('AUTOMATION.TIME_WINDOW.SUMMARY_WEEKDAYS');
  }
  const dayLabels = {
    sun: t('DAYS_OF_WEEK.SUNDAY'),
    mon: t('DAYS_OF_WEEK.MONDAY'),
    tue: t('DAYS_OF_WEEK.TUESDAY'),
    wed: t('DAYS_OF_WEEK.WEDNESDAY'),
    thu: t('DAYS_OF_WEEK.THURSDAY'),
    fri: t('DAYS_OF_WEEK.FRIDAY'),
    sat: t('DAYS_OF_WEEK.SATURDAY'),
  };
  return selectedDays.map(day => dayLabels[day].slice(0, 3)).join(', ');
};

export const summarizeTimeWindow = (
  value,
  t,
  { negate = false, withZone = false } = {}
) => {
  const parsed = parseTimeWindow(Array.isArray(value) ? value[0] : value);
  if (!parsed || getTimeWindowState(parsed) !== 'valid') return '';
  const days = summarizeDays(
    TIME_WINDOW_DAYS.filter(day => parsed.days.includes(day)),
    t
  );
  if (!withZone) return `${parsed.from}–${parsed.to} · ${days}`;

  const summaryParams = { from: parsed.from, to: parsed.to, days };
  const summary = negate
    ? t('AUTOMATION.TIME_WINDOW.SUMMARY_OUT', summaryParams)
    : t('AUTOMATION.TIME_WINDOW.SUMMARY_IN', summaryParams);
  const overnight = parsed.to < parsed.from;
  const zone = t('AUTOMATION.TIME_WINDOW.INBOX_TIME_ZONE');
  return [
    summary,
    ...(overnight ? [t('AUTOMATION.TIME_WINDOW.OVERNIGHT')] : []),
    zone,
  ].join(' · ');
};
