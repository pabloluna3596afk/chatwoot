import {
  META_LANGUAGES,
  defaultLanguage,
  languageLabel,
  languageOptions,
  rememberLanguage,
} from '../whatsappLanguages';

describe('whatsappLanguages', () => {
  beforeEach(() => window.localStorage.clear());

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

  it('starts a template in the language used last, else the account language, else Spanish', () => {
    expect(defaultLanguage('pt_BR')).toBe('pt_BR');
    expect(defaultLanguage('xx')).toBe('es');
    expect(defaultLanguage(undefined)).toBe('es');

    rememberLanguage('es_EC');
    expect(defaultLanguage('pt_BR')).toBe('es_EC');
  });
});
