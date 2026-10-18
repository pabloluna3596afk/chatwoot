import { getTimezone } from 'countries-and-timezones';
import { accountTimeZoneOptions } from 'dashboard/helper/timeZoneOptions';

export const businessTimezoneOptions = (current, locale, date = new Date()) => {
  const languageTag = locale.replace('_', '-');
  const countryNames = new Intl.DisplayNames([languageTag], { type: 'region' });

  return accountTimeZoneOptions(current).map(({ value }) => {
    const city = value.split('/').pop().replace(/_/g, ' ');
    const countryCodes = getTimezone(value)?.countries || [];
    const countries = countryCodes.map(code => countryNames.of(code));
    const offset = new Intl.DateTimeFormat(languageTag, {
      timeZone: value,
      timeZoneName: 'shortOffset',
    })
      .formatToParts(date)
      .find(part => part.type === 'timeZoneName').value;

    return {
      value,
      label: `${countries.length ? `${countries[0]} ` : ''}(${offset}) · ${city}`,
      searchTerms: [value, city, ...countries],
    };
  });
};
