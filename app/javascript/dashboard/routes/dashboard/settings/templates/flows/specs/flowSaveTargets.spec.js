import { saveTargets } from '../flowSaveTargets';

const attributes = [
  {
    attribute_key: 'company_context',
    attribute_model: 'company_attribute',
    attribute_display_type: 'text',
  },
  {
    attribute_key: 'birthday',
    attribute_model: 'contact_attribute',
    attribute_display_type: 'date',
  },
  {
    attribute_key: 'accept',
    attribute_model: 'contact_attribute',
    attribute_display_type: 'checkbox',
  },
  {
    attribute_key: 'choices',
    attribute_model: 'contact_attribute',
    attribute_display_type: 'list',
    attribute_values: ['a'],
  },
  {
    attribute_key: 'count',
    attribute_model: 'contact_attribute',
    attribute_display_type: 'number',
  },
  {
    attribute_key: 'computed',
    attribute_model: 'contact_attribute',
    attribute_display_type: 'number',
    formula: { op: 'count' },
  },
  {
    attribute_key: 'context',
    attribute_model: 'conversation_attribute',
    attribute_display_type: 'text',
  },
];
const keys = block =>
  saveTargets(block, attributes).map(binding => binding.key);

describe('writable template bindings for flow answers', () => {
  it('keeps the exact writable standard vocabulary and excludes conversation/agent values', () => {
    expect(keys({ type: 'short_text' })).toEqual([
      'contact.name',
      'contact.email',
      'contact.phone',
      'contact.company_name',
      'contact.city',
      'contact.document_number',
    ]);
  });
  it('restricts booleans, numbers, dates and files by type', () => {
    expect(keys({ type: 'optin' })).toEqual([
      'contact.custom_attribute.accept',
    ]);
    expect(keys({ type: 'short_text', input: 'number' })).toContain(
      'contact.custom_attribute.count'
    );
    expect(keys({ type: 'short_text', input: 'number' })).not.toContain(
      'contact.custom_attribute.computed'
    );
    expect(keys({ type: 'date' })).toContain(
      'contact.custom_attribute.birthday'
    );
    expect(keys({ type: 'photo' })).toEqual([]);
  });
  it('allows compatible list values for single choice, but only text for multi-checkbox', () => {
    expect(keys({ type: 'dropdown', options: [{ id: 'a' }] })).toContain(
      'contact.custom_attribute.choices'
    );
    expect(keys({ type: 'dropdown', options: [{ id: 'b' }] })).not.toContain(
      'contact.custom_attribute.choices'
    );
    expect(keys({ type: 'checkbox', options: [{ id: 'a' }] })).not.toContain(
      'contact.custom_attribute.choices'
    );
  });
});

// Fixed expected results cover every Flow block kind; metadata must not change the destinations.
describe('Flow destination matrix regression', () => {
  const textKeys = [
    'contact.name',
    'contact.email',
    'contact.phone',
    'contact.company_name',
    'contact.city',
    'contact.document_number',
  ];
  it.each([
    [{ type: 'short_text' }, []],
    [
      { type: 'short_text', input: 'number' },
      ['contact.custom_attribute.count'],
    ],
    [{ type: 'long_text' }, []],
    [{ type: 'checkbox' }, []],
    [{ type: 'date' }, ['contact.custom_attribute.birthday']],
    [
      { type: 'dropdown', options: [{ id: 'a' }] },
      ['contact.custom_attribute.choices'],
    ],
    [
      { type: 'radio', options: [{ id: 'a' }] },
      ['contact.custom_attribute.choices'],
    ],
    [{ type: 'radio', options: [{ id: 'b' }] }, []],
  ])(
    'preserves ordered text and compatible custom targets for %j',
    (block, extra) => {
      expect(keys(block)).toEqual([...textKeys, ...extra]);
    }
  );
  it.each(['photo', 'document', 'heading', 'body', 'unknown'])(
    'never offers a target for %s',
    type => {
      expect(keys({ type })).toEqual([]);
    }
  );
});
