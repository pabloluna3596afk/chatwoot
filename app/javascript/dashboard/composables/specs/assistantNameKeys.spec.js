import en from 'dashboard/i18n/locale/en/integrations.json';
import es from 'dashboard/i18n/locale/es/integrations.json';

const sources = import.meta.glob(
  [
    '../../components-next/captain/**/*.vue',
    '../../routes/dashboard/captain/**/*.vue',
  ],
  { eager: true, query: '?raw', import: 'default' }
);

const flatten = (object, prefix = '') =>
  Object.fromEntries(
    Object.entries(object).flatMap(([key, value]) => {
      const path = prefix ? `${prefix}.${key}` : key;
      return typeof value === 'object'
        ? Object.entries(flatten(value, path))
        : [[path, value]];
    })
  );

describe('assistant name translation boundary', () => {
  it('snapshots the exact upstream keys rendered through nameRichFrom / nameTextFrom', () => {
    const keys = Object.values(sources).flatMap(source =>
      [...source.matchAll(/name(?:Rich|Text)From\(\s*t\(\s*'([^']+)'/g)].map(
        match => match[1]
      )
    );
    const schedule = Object.values(sources).find(source =>
      source.includes('const RESPONSE_WINDOW =')
    );
    expect(schedule).toMatch(
      /name(?:Rich|Text)From\(\s*t\(`CAPTAIN\.ASSISTANTS\.FORM\.SCHEDULE\.\$\{option\.toUpperCase\(\)\}\.DESC`\)/
    );
    keys.push(
      ...['ALWAYS', 'BUSINESS_HOURS', 'OUTSIDE_BUSINESS_HOURS'].map(
        option => `CAPTAIN.ASSISTANTS.FORM.SCHEDULE.${option}.DESC`
      )
    );
    const uniqueKeys = [...new Set(keys)].sort();
    expect(uniqueKeys).toHaveLength(38);
    expect(uniqueKeys).toMatchSnapshot();
    const spanish = flatten(es);
    const english = flatten(en);
    uniqueKeys.forEach(key => {
      expect(spanish[key]).toContain('Captain');
      expect(english[key]).toContain('Captain');
    });
  });

  it('keeps parity for the 40 owned name placeholders without CJK', () => {
    const spanish = flatten(es);
    const english = flatten(en);
    const ownedKeys = Object.keys(spanish).filter(key =>
      spanish[key].includes('{assistantName}')
    );
    expect(ownedKeys).toEqual(
      Object.keys(english).filter(key =>
        english[key].includes('{assistantName}')
      )
    );
    // Two existing keys already interpolated the assistant name before this change.
    expect(ownedKeys).toHaveLength(42);
    ownedKeys.forEach(key => {
      expect(spanish[key] + english[key]).not.toMatch(
        /[\u3040-\u30ff\u3400-\u9fff]/
      );
    });
  });
});
