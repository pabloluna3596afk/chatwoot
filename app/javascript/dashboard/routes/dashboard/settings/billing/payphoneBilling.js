export const shouldShowPayphoneRenewalDate = renewalState =>
  !['grace', 'expired'].includes(renewalState);
