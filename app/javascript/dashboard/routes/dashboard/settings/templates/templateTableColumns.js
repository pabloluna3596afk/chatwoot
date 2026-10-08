export const COMMON_COLUMNS = [
  'NAME',
  'CATEGORY',
  'INBOX',
  'STATUS',
  'UPDATED',
  'ACTIONS',
];

export const templateTableColumns = (t, specific = []) =>
  [...COMMON_COLUMNS.slice(0, 2), ...specific, ...COMMON_COLUMNS.slice(2)].map(
    key => ({
      key,
      label: t(`WHATSAPP_TEMPLATE_MGMT.TABLE.${key}`),
    })
  );
