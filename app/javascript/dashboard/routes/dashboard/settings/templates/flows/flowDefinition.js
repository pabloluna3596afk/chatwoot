// The ChatHub form ("flow") definition in the dashboard: its blocks, the starting points, the names of the answers and
// the show/hide conditions. The shape is the one of Whatsapp::Flows::Spec (the server checks it and exports it to
// Meta's Flow JSON); the limits are only used here to keep the inputs honest.

import { CONDITION_TYPES } from 'shared/helpers/flowAnswers';

export const BLOCK_TYPES = [
  { type: 'heading', group: 'text', icon: 'i-lucide-heading-1' },
  { type: 'subheading', group: 'text', icon: 'i-lucide-heading-2' },
  { type: 'text', group: 'text', icon: 'i-lucide-text' },
  { type: 'caption', group: 'text', icon: 'i-lucide-text-quote' },
  { type: 'short_text', group: 'answer', icon: 'i-lucide-text-cursor-input' },
  { type: 'long_text', group: 'answer', icon: 'i-lucide-align-left' },
  { type: 'dropdown', group: 'answer', icon: 'i-lucide-chevrons-up-down' },
  { type: 'radio', group: 'answer', icon: 'i-lucide-circle-dot' },
  { type: 'checkbox', group: 'answer', icon: 'i-lucide-square-check' },
  { type: 'date', group: 'answer', icon: 'i-lucide-calendar' },
  { type: 'optin', group: 'answer', icon: 'i-lucide-badge-check' },
  { type: 'photo', group: 'file', icon: 'i-lucide-image' },
  { type: 'document', group: 'file', icon: 'i-lucide-file-text' },
];

// The buttons of the builder's "add to the screen" column, in the order of the page. `id` names the button (and its
// label); email, phone and number are a short text with that kind of answer.
export const PALETTE = [
  {
    group: 'text',
    items: [
      { id: 'heading', type: 'heading', icon: 'i-lucide-heading-1' },
      { id: 'subheading', type: 'subheading', icon: 'i-lucide-heading-2' },
      { id: 'text', type: 'text', icon: 'i-lucide-text' },
      { id: 'caption', type: 'caption', icon: 'i-lucide-text-quote' },
    ],
  },
  {
    group: 'answer',
    items: [
      {
        id: 'short_text',
        type: 'short_text',
        icon: 'i-lucide-text-cursor-input',
      },
      {
        id: 'email',
        type: 'short_text',
        input: 'email',
        icon: 'i-lucide-at-sign',
      },
      {
        id: 'phone',
        type: 'short_text',
        input: 'phone',
        icon: 'i-lucide-phone',
      },
      {
        id: 'number',
        type: 'short_text',
        input: 'number',
        icon: 'i-lucide-hash',
      },
      { id: 'long_text', type: 'long_text', icon: 'i-lucide-align-left' },
      { id: 'date', type: 'date', icon: 'i-lucide-calendar' },
    ],
  },
  {
    group: 'options',
    items: [
      { id: 'radio', type: 'radio', icon: 'i-lucide-circle-dot' },
      { id: 'checkbox', type: 'checkbox', icon: 'i-lucide-square-check' },
      { id: 'dropdown', type: 'dropdown', icon: 'i-lucide-chevrons-up-down' },
      { id: 'optin', type: 'optin', icon: 'i-lucide-badge-check' },
    ],
  },
  {
    group: 'file',
    items: [
      { id: 'photo', type: 'photo', icon: 'i-lucide-image' },
      { id: 'document', type: 'document', icon: 'i-lucide-file-text' },
    ],
  },
];

export const TEXT_TYPES = ['heading', 'subheading', 'text', 'caption'];
export const OPTION_TYPES = ['dropdown', 'radio', 'checkbox'];
export const FILE_TYPES = ['photo', 'document'];
export const INPUT_KINDS = ['text', 'email', 'phone', 'number'];
// What the builder offers as the question of a new condition: pick-one questions.
export const SINGLE_CHOICE_TYPES = ['dropdown', 'radio'];
// What a condition can look at: one answer, not a list or a file.
export { CONDITION_TYPES } from 'shared/helpers/flowAnswers';
export const CATEGORIES = [
  'LEAD_GENERATION',
  'SIGN_UP',
  'SIGN_IN',
  'APPOINTMENT_BOOKING',
  'CONTACT_US',
  'CUSTOMER_SUPPORT',
  'SURVEY',
  'OTHER',
];

export const LIMITS = {
  screenTitle: 30,
  footer: 35,
  heading: 80,
  subheading: 80,
  text: 4096,
  caption: 409,
  keyLabel: 20,
  choiceLabel: 30,
  dateLabel: 40,
  optinLabel: 120,
  fileLabel: 80,
  helper: 80,
  optionTitle: 30,
};

const LABEL_LIMIT = {
  short_text: 'keyLabel',
  long_text: 'keyLabel',
  dropdown: 'keyLabel',
  radio: 'choiceLabel',
  checkbox: 'choiceLabel',
  date: 'dateLabel',
  optin: 'optinLabel',
  photo: 'fileLabel',
  document: 'fileLabel',
};

export const labelLimit = type => LIMITS[LABEL_LIMIT[type]];
export const textLimit = type => LIMITS[type];

export const isAnswer = block => !TEXT_TYPES.includes(block.type);

// "Número de cédula" -> "numero_de_cedula": the name an answer is sent back with.
export const slugify = value =>
  String(value || '')
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '_')
    .replace(/^_+|_+$/g, '')
    .replace(/^[0-9]+/, '')
    .replace(/^_+/, '')
    .slice(0, 40);

// Every answer of the form, in order: { screen, block, key, type, definition }.
export const fieldsOf = definition =>
  (definition.screens || []).flatMap((screen, screenIndex) =>
    (screen.blocks || []).flatMap((block, blockIndex) =>
      isAnswer(block)
        ? [
            {
              screen: screenIndex,
              block: blockIndex,
              key: block.key,
              type: block.type,
              definition: block,
            },
          ]
        : []
    )
  );

// The first name that is free: "nombre", "nombre_2", "nombre_3"...
export const uniqueKey = (base, taken) => {
  const root = slugify(base) || 'campo';
  if (!taken.includes(root)) return root;
  let counter = 2;
  while (taken.includes(`${root}_${counter}`)) counter += 1;
  return `${root}_${counter}`;
};

const takenKeys = definition => fieldsOf(definition).map(field => field.key);

export const newBlock = (type, definition = { screens: [] }) => {
  if (TEXT_TYPES.includes(type)) return { type, text: '' };
  const block = {
    type,
    key: uniqueKey(type === 'optin' ? 'acepto' : type, takenKeys(definition)),
    label: '',
    required: false,
  };
  if (type === 'short_text') block.input = 'text';
  if (OPTION_TYPES.includes(type)) {
    block.options = [
      { id: 'opcion_1', title: '' },
      { id: 'opcion_2', title: '' },
    ];
  }
  if (FILE_TYPES.includes(type)) block.max_files = 1;
  return block;
};

// `number` is the position of the new screen, which names it until the user gives it a title.
export const newScreen = number => ({
  title: `Pantalla ${number}`,
  button: '',
  blocks: [],
});

export const newOption = block => {
  const taken = (block.options || []).map(option => option.id);
  return { id: uniqueKey('opcion', taken), title: '' };
};

// An option's id comes from its title, once, so answers keep their name when the title is reworded.
export const optionIdFor = (title, block, index) => {
  const taken = (block.options || [])
    .filter((_, position) => position !== index)
    .map(option => option.id);
  return uniqueKey(title || 'opcion', taken);
};

export const emptyDefinition = () => ({
  schema_version: 1,
  screens: [],
});

// The answers that come before a block, the ones a condition can look at.
export const conditionSources = (definition, screenIndex, blockIndex) =>
  fieldsOf(definition).filter(
    field =>
      CONDITION_TYPES.includes(field.type) &&
      (field.screen < screenIndex ||
        (field.screen === screenIndex && field.block < blockIndex))
  );

export const defaultCondition = source => {
  if (!source) return null;
  const options = source.definition.options || [];
  let value = '';
  if (source.type === 'optin') value = 'true';
  else if (options.length) value = options[0].id;
  return { key: source.key, op: 'equals', value };
};

// Whether a block shows, given the answers filled in so far (the preview and the CRM render use the same rule).
export { evaluateVisibility as isVisible } from 'shared/helpers/flowAnswers';

// Meta's starting points of a new form, in ChatHub's words. `definition` is what the preview shows before creating.
const optionList = titles =>
  titles.map(title => ({ id: slugify(title), title }));

export const STARTING_POINTS = {
  blank: () => ({
    schema_version: 1,
    screens: [newScreen(1)],
  }),
  interests: () => ({
    schema_version: 1,
    screens: [
      {
        title: 'Tus intereses',
        button: 'Enviar',
        blocks: [
          { type: 'heading', text: '¿Qué te interesa?' },
          {
            type: 'checkbox',
            key: 'intereses',
            label: 'Elige tus temas',
            required: true,
            options: optionList(['Novedades', 'Promociones', 'Citas', 'Otro']),
          },
          {
            type: 'short_text',
            key: 'otro_interes',
            label: '¿Cuál otro?',
            input: 'text',
          },
        ],
      },
    ],
  }),
  feedback: () => ({
    schema_version: 1,
    screens: [
      {
        title: 'Tu opinión',
        button: 'Enviar',
        blocks: [
          { type: 'heading', text: 'Cuéntanos cómo te fue' },
          {
            type: 'radio',
            key: 'calificacion',
            label: 'Tu calificación',
            required: true,
            options: optionList(['Excelente', 'Buena', 'Regular', 'Mala']),
          },
          {
            type: 'long_text',
            key: 'comentarios',
            label: 'Comentarios',
            helper: 'Cuéntanos qué podemos mejorar',
          },
        ],
      },
    ],
  }),
  survey: () => ({
    schema_version: 1,
    screens: [
      {
        title: 'Sobre ti',
        button: 'Continuar',
        blocks: [
          { type: 'heading', text: 'Encuesta rápida' },
          {
            type: 'short_text',
            key: 'nombre',
            label: 'Tu nombre',
            required: true,
            input: 'text',
          },
          {
            type: 'dropdown',
            key: 'medio',
            label: '¿Cómo nos conociste?',
            required: true,
            options: optionList(['Redes sociales', 'Un amigo', 'Otro']),
          },
        ],
      },
      {
        title: 'Tu experiencia',
        button: 'Enviar',
        blocks: [
          {
            type: 'radio',
            key: 'satisfaccion',
            label: 'Satisfacción',
            required: true,
            options: optionList(['Muy satisfecho', 'Satisfecho', 'Poco']),
          },
          { type: 'long_text', key: 'sugerencias', label: 'Sugerencias' },
        ],
      },
    ],
  }),
  support: () => ({
    schema_version: 1,
    screens: [
      {
        title: 'Atención al cliente',
        button: 'Enviar',
        blocks: [
          { type: 'heading', text: '¿En qué te ayudamos?' },
          {
            type: 'short_text',
            key: 'nombre',
            label: 'Tu nombre',
            required: true,
            input: 'text',
          },
          {
            type: 'short_text',
            key: 'correo',
            label: 'Correo',
            input: 'email',
          },
          {
            type: 'dropdown',
            key: 'tema',
            label: 'Tema',
            required: true,
            options: optionList(['Facturación', 'Soporte técnico', 'Otro']),
          },
          {
            type: 'short_text',
            key: 'detalle_tema',
            label: '¿Cuál?',
            input: 'text',
            visible_when: { key: 'tema', op: 'equals', value: 'otro' },
          },
          {
            type: 'long_text',
            key: 'mensaje',
            label: 'Mensaje',
            required: true,
          },
        ],
      },
    ],
  }),
};

export const startingDefinition = id =>
  (STARTING_POINTS[id] || STARTING_POINTS.blank)();

// Meta's error code is mapped to a key of WHATSAPP_FLOWS.ERRORS; its place in the form to the screen and block.
export const errorPlace = path => {
  const match = String(path || '').match(/^screens\.(\d+)(?:\.blocks\.(\d+))?/);
  if (!match) return { screen: null, block: null };
  return {
    screen: Number(match[1]),
    block: match[2] === undefined ? null : Number(match[2]),
  };
};

// The errors of the server grouped by where they are: { screen: { 0: [...] }, block: { '0.2': [...] }, form: [...] }.
export const groupErrors = errors => {
  const grouped = { form: [], screen: {}, block: {} };
  (errors || []).forEach(error => {
    const place = errorPlace(error.path);
    if (place.screen === null) grouped.form.push(error);
    else if (place.block === null)
      (grouped.screen[place.screen] ||= []).push(error);
    else (grouped.block[`${place.screen}.${place.block}`] ||= []).push(error);
  });
  return grouped;
};
