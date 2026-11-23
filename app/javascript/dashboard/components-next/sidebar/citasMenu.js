export const buildCitasMenu = ({
  isAdmin,
  hasCalendars,
  hasGoogleConnection,
  t,
  accountScopedRoute,
}) =>
  isAdmin && hasCalendars && hasGoogleConnection
    ? [
        {
          name: 'Settings Citas',
          label: t('SIDEBAR.CITAS'),
          icon: 'i-lucide-calendar-days',
          to: accountScopedRoute('settings_citas'),
        },
      ]
    : [];
