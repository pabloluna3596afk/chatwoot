import {
  META_LANGUAGES,
  defaultLanguage,
  languageLabel,
  languageOptions,
} from '../whatsappLanguages';

describe('whatsappLanguages', () => {
  it('lists the Meta languages, including the Spanish of each country', () => {
    ['es', 'es_EC', 'es_MX', 'es_AR', 'es_CO', 'pt_BR', 'en_US'].forEach(code =>
      expect(META_LANGUAGES).toContain(code)
    );
    expect(new Set(META_LANGUAGES).size).toBe(META_LANGUAGES.length);
  });

  it('writes the name the way Meta lists it, in the language of the screen', () => {
    expect(languageLabel('es_EC', 'es')).toBe('Español (Ecuador)');
    expect(languageLabel('es', 'es')).toBe('Español');
    expect(languageLabel('en_US', 'es')).toMatch(/^Inglés/);
    expect(languageLabel('', 'es')).toBe('—');
  });

  it('gives one option per language, sorted by name', () => {
    const options = languageOptions('es');
    expect(options).toHaveLength(META_LANGUAGES.length);
    expect(options.find(option => option.value === 'es_EC').label).toBe(
      'Español (Ecuador)'
    );
    const labels = options.map(option => option.label);
    expect(labels).toEqual([...labels].sort((a, b) => a.localeCompare(b)));
  });

  it('starts a template in the language most of the templates of the channel use, else the account language, else Spanish', () => {
    const templates = [
      { language: 'es_EC', inboxes: [{ id: 1 }] },
      { language: 'es_EC', inboxes: [{ id: 1 }] },
      { language: 'en_US', inboxes: [{ id: 1 }] },
      { language: 'pt_BR', inboxes: [{ id: 2 }] },
      { language: 'pt_BR', inboxes: [{ id: 2 }] },
      { language: 'pt_BR', inboxes: [{ id: 2 }] },
    ];
    expect(defaultLanguage('es', templates, 1)).toBe('es_EC');
    expect(defaultLanguage('es', templates, 2)).toBe('pt_BR');
    expect(defaultLanguage('en', [], 1)).toBe('en');
    expect(defaultLanguage('xx', [], 1)).toBe('es');
    expect(defaultLanguage(undefined)).toBe('es');
  });
});
