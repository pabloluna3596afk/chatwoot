import { createI18n } from 'vue-i18n';
import en from '../../i18n/locale/en/conversation.json';
import es from '../../i18n/locale/es/conversation.json';
import {
  resolvePreviewText,
  formatMacroPreviewValue,
} from '../shortcutPreview';

const { t } = createI18n({
  legacy: false,
  locale: 'es',
  messages: { es },
}).global;

it.each([undefined, null, ''])('marks an unset variable (%s)', value => {
  expect(
    resolvePreviewText(
      'Hola {{contact.name}}',
      { 'contact.name': value },
      'sin valor'
    )
  ).toBe('Hola `sin valor`');
});

it('uses the sending resolver, preserves zero/false and marks missing or deferred Liquid', () => {
  expect(
    resolvePreviewText(
      '{{ contact.name }} {{agent.name}} {{conversation.custom_attribute.monto}} {{flag}} {{missing}} {{deferred}}',
      {
        'contact.name': 'Ana',
        'agent.name': 'Luis',
        'conversation.custom_attribute.monto': 0,
        flag: false,
        deferred: '{{ date.today }}',
      },
      'sin valor'
    )
  ).toBe('Ana Luis 0 false `sin valor` `sin valor`');
});

it.each([
  ['{{ date.today | plus_days: 15 }}', 'hoy + 15 días'],
  ['{{date.today|minus_days: 2}}', 'hoy − 2 días'],
  ['{{date.today}}', 'hoy'],
  [
    {
      attribute_key: 'fecha_seguimiento',
      value: '{{ date.today | plus_days: 15 }}',
    },
    'fecha_seguimiento = hoy + 15 días',
  ],
  [{ attribute_key: 'monto', value: 0 }, 'monto = 0'],
  [{ attribute_key: 'activo', value: false }, 'activo = false'],
  [
    { nested: { amount: 12 }, tags: ['a', 'b'] },
    'nested = amount = 12\ntags = a, b',
  ],
])('makes macro data readable: %j', (value, expected) => {
  expect(formatMacroPreviewValue(value, {}, t)).toBe(expected);
});

it('keeps the added English and Spanish keys in exact parity', () => {
  const english = en.CONVERSATION.PICKER.PREVIEW;
  const spanish = es.CONVERSATION.PICKER.PREVIEW;
  expect(Object.keys(english)).toEqual(Object.keys(spanish));
  expect(Object.keys(english.STATUS)).toEqual(Object.keys(spanish.STATUS));
  expect(english.MISSING).toBe('no value');
  expect(spanish.MISSING).toBe('sin valor');
});
