// ChatHub's ready-made WhatsApp templates (Spanish, neutral "tú", no emoji). Picking one opens the template form
// filled in; nothing goes to Meta until the administrator saves it.
//
// Variables are named so it is obvious what each one is: {{nombre}}, {{cita}}, {{fecha}}, {{hora}}, {{tema}}. The
// appointment ones are the names Captain's reminders fill in by themselves when the template is picked in its
// settings (nombre, cita, fecha, hora). The category is chosen for each one:
//  - UTILITY confirms or updates something the customer already booked or asked for, with no sales language;
//  - MARKETING invites to come back, buy or resume a conversation (Meta bills it higher and would re-classify a
//    utility template with promotional text anyway, so it is labelled honestly).
import { emptyForm, newButton } from './templateForm';

export const PRESET_GROUPS = ['APPOINTMENTS', 'FOLLOWUP', 'CUSTOMER_DATA'];

const OPT_OUT = 'Responde BAJA si no quieres recibir más mensajes';

const quickReplies = (...texts) =>
  texts.map(text => ({ ...newButton('QUICK_REPLY'), text }));

export const PRESETS = [
  {
    id: 'recordatorio_cita',
    group: 'APPOINTMENTS',
    category: 'UTILITY',
    body: 'Hola {{nombre}}, te recordamos tu cita "{{cita}}" el {{fecha}} a las {{hora}}. ¿Nos confirmas que asistirás?',
    examples: ['Ana', 'Consulta', 'jueves 8 de octubre', '10:30'],
    buttons: ['Confirmo', 'Cambiar hora', 'Cancelar cita'],
  },
  {
    id: 'confirmar_asistencia_cita',
    group: 'APPOINTMENTS',
    category: 'UTILITY',
    body: 'Hola {{nombre}}, tienes una cita "{{cita}}" el {{fecha}} a las {{hora}}. Por favor confirma si podrás asistir.',
    examples: ['Ana', 'Consulta', 'jueves 8 de octubre', '10:30'],
    buttons: ['Sí, asistiré', 'No podré asistir'],
  },
  {
    id: 'cita_cancelada',
    group: 'APPOINTMENTS',
    category: 'UTILITY',
    body: 'Hola {{nombre}}, tu cita "{{cita}}" del {{fecha}} a las {{hora}} fue cancelada. Si quieres agendar otra, responde a este mensaje.',
    examples: ['Ana', 'Consulta', 'jueves 8 de octubre', '10:30'],
    buttons: ['Agendar otra cita'],
  },
  {
    id: 'cita_cambiada',
    group: 'APPOINTMENTS',
    category: 'UTILITY',
    body: 'Hola {{nombre}}, tu cita "{{cita}}" cambió: ahora es el {{fecha}} a las {{hora}}. Si no te conviene, responde a este mensaje y buscamos otro horario.',
    examples: ['Ana', 'Consulta', 'jueves 8 de octubre', '10:30'],
    buttons: ['Confirmo', 'Cambiar hora'],
  },
  {
    id: 'reenganche_conversacion',
    group: 'FOLLOWUP',
    category: 'MARKETING',
    body: 'Hola {{nombre}}, hace unos días conversamos y quedó pendiente ayudarte con {{tema}}. ¿Todavía te interesa? Responde a este mensaje y lo retomamos.',
    examples: ['Ana', 'tu consulta'],
    footer: OPT_OUT,
    buttons: ['Sí, continuar', 'Ya no, gracias'],
  },
  {
    id: 'seguimiento_cotizacion',
    group: 'FOLLOWUP',
    category: 'MARKETING',
    body: 'Hola {{nombre}}, queríamos saber si pudiste revisar la información sobre {{tema}}. Si tienes dudas, escríbenos y te ayudamos.',
    examples: ['Ana', 'el plan que consultaste'],
    footer: OPT_OUT,
    buttons: ['Tengo una duda'],
  },
  {
    id: 'seguimiento_servicio',
    group: 'FOLLOWUP',
    category: 'UTILITY',
    body: 'Hola {{nombre}}, gracias por tu visita. ¿Cómo te fue con {{tema}}? Tu opinión nos ayuda a mejorar.',
    examples: ['Ana', 'la atención de hoy'],
    buttons: ['Muy bien', 'Podría mejorar'],
  },
  {
    // Needs a published WhatsApp form (the FLOW button): it arrives with the form creator, so the card is shown
    // but cannot be used yet.
    id: 'datos_cliente',
    group: 'CUSTOMER_DATA',
    category: 'UTILITY',
    disabled: true,
    body: 'Hola {{nombre}}, para continuar necesitamos tus datos. Completa el formulario con el botón de abajo.',
    examples: ['Ana'],
    buttons: [],
  },
];

// The template form filled in with a preset (the name is the preset's id, the admin can change it).
export const presetToForm = (preset, inboxId = null) => {
  const form = emptyForm();
  form.inboxId = inboxId;
  form.name = preset.id;
  form.category = preset.category;
  form.body = { text: preset.body, examples: [...preset.examples] };
  form.footer = { text: preset.footer || '' };
  form.buttons = quickReplies(...preset.buttons);
  return form;
};
