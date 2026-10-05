// The text of the invitation of an appointment (what the customer reads in the Google Calendar event), in the dashboard:
// the variables it can use and the same filling-in the server does (Integrations::GoogleCalendar::InvitationText), so the
// preview shows what will be sent. Keep both in step.

export const INVITATION_TOKENS = [
  'nombre',
  'primer_nombre',
  'telefono',
  'correo',
  'agente',
  'empresa',
  'fecha',
  'hora',
  'motivo',
  'direccion',
  'enlace_meet',
  'conversacion',
];

const TOKEN = /\{\{\s*([a-z_]+)\s*\}\}/g;

const knownTokens = line =>
  [...line.matchAll(TOKEN)]
    .map(match => match[1])
    .filter(token => INVITATION_TOKENS.includes(token));

// The variables of a text that do not exist (a typo).
export const unknownTokens = template => [
  ...new Set(
    [...String(template || '').matchAll(TOKEN)]
      .map(match => match[1])
      .filter(token => !INVITATION_TOKENS.includes(token))
  ),
];

// A line whose variables are all empty is left out; what is not a known variable stays as it was typed.
export const renderInvitation = (template, values) => {
  const lines = String(template || '')
    .replace(/\r\n/g, '\n')
    .split('\n')
    .filter(line => {
      const known = knownTokens(line);
      return !known.length || known.some(token => values[token]);
    })
    .map(line =>
      line.replace(TOKEN, (match, token) =>
        INVITATION_TOKENS.includes(token) ? values[token] || '' : match
      )
    );
  return lines
    .join('\n')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
};

const upperFirst = text => text.charAt(0).toUpperCase() + text.slice(1);

// "jueves 8 de octubre" / "Thursday, October 8", from a YYYY-MM-DD date.
export const dayText = (date, locale = 'es') => {
  const [year, month, day] = String(date || '')
    .split('-')
    .map(Number);
  if (!year || !month || !day) return '';
  const parts = new Intl.DateTimeFormat(locale, {
    weekday: 'long',
    day: 'numeric',
    month: 'long',
    timeZone: 'UTC',
  }).formatToParts(new Date(Date.UTC(year, month - 1, day)));
  const part = type => parts.find(item => item.type === type)?.value || '';
  return locale.startsWith('es')
    ? `${part('weekday')} ${part('day')} de ${part('month')}`
    : `${part('weekday')}, ${part('month')} ${part('day')}`;
};

// The values of an appointment as the modal knows them. What it cannot know yet (the Meet link, before Google creates it)
// is empty.
export const invitationValues = ({
  contactName = '',
  contactEmail = '',
  contactPhone = '',
  agentName = '',
  accountName = '',
  date = '',
  time = '',
  summary = '',
  location = '',
  meetLink = '',
  conversationId = '',
  locale = 'es',
}) => {
  const name = String(contactName || '').trim();
  const first = name.split(/\s+/)[0] || '';
  return {
    nombre: name,
    primer_nombre: first ? upperFirst(first.toLowerCase()) : '',
    telefono: contactPhone || '',
    correo: contactEmail || '',
    agente: agentName || '',
    empresa: accountName || '',
    fecha: dayText(date, locale),
    hora: time || '',
    motivo: summary || '',
    direccion: location || '',
    enlace_meet: meetLink || '',
    conversacion: conversationId ? `#${conversationId}` : '',
  };
};

// Made-up values for the settings preview.
export const sampleValues = (locale = 'es', location = '') => {
  const tomorrow = new Date(Date.now() + 24 * 60 * 60 * 1000)
    .toISOString()
    .slice(0, 10);
  return invitationValues({
    contactName: 'Ana Pérez',
    contactEmail: 'ana@ejemplo.com',
    contactPhone: '+593 99 999 9999',
    agentName: 'Aurora',
    accountName: 'Tu empresa',
    date: tomorrow,
    time: '10:30',
    summary: 'Consulta',
    location,
    meetLink: 'https://meet.google.com/abc-defg-hij',
    conversationId: '123',
    locale,
  });
};
