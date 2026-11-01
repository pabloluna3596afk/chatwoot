import { shouldShowPayphoneRenewalDate } from '../payphoneBilling';
import enSettings from 'dashboard/i18n/locale/en/settings.json';
import esSettings from 'dashboard/i18n/locale/es/settings.json';

describe('Payphone billing dates', () => {
  it('does not show a renewal date after the paid period ends', () => {
    expect(shouldShowPayphoneRenewalDate('grace')).toBe(false);
    expect(shouldShowPayphoneRenewalDate('expired')).toBe(false);
  });

  it('keeps the renewal date while the paid period is current', () => {
    expect(shouldShowPayphoneRenewalDate('due_soon')).toBe(true);
    expect(shouldShowPayphoneRenewalDate(null)).toBe(true);
  });

  it('labels the actual expiration and access end in both supported product locales', () => {
    expect(esSettings.PAYPHONE.RENEWAL.grace).toBe(
      'Tu plan venció el {date}. Acceso hasta el {grace_end}.'
    );
    expect(enSettings.PAYPHONE.RENEWAL.grace).toBe(
      'Your plan ended on {date}. Access until {grace_end}.'
    );
    expect(esSettings.PAYPHONE.RENEWAL.expired).toBe('Plan gratuito.');
    expect(enSettings.PAYPHONE.RENEWAL.expired).toBe('Free plan.');
  });
});
