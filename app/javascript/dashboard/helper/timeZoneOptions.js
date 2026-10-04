export const DEFAULT_ACCOUNT_TIMEZONE = 'America/Guayaquil';

// IANA zones the browser knows, for the account time zone select. Keeps the saved value in the list
// even when the browser does not list it.
export const accountTimeZoneOptions = (current = '') => {
  let zones = [];
  try {
    zones = Intl.supportedValuesOf('timeZone');
  } catch (error) {
    zones = [];
  }
  const ids = new Set([DEFAULT_ACCOUNT_TIMEZONE, ...zones]);
  if (current) ids.add(current);
  return [...ids]
    .sort()
    .map(id => ({ label: id.replace(/_/g, ' '), value: id }));
};
