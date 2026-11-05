const DATE_OPTIONS = { day: 'numeric', month: 'short', year: 'numeric' };

export const formatBillingDate = (value, locale) =>
  new Intl.DateTimeFormat(locale, DATE_OPTIONS).format(new Date(value));

export const formatBillingDateRange = (start, end, locale) =>
  new Intl.DateTimeFormat(locale, DATE_OPTIONS).formatRange(
    new Date(start),
    new Date(end)
  );
