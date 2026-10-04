// The languages a WhatsApp template can be written in (Meta's list of supported template languages).
export const META_LANGUAGES = [
  'af',
  'sq',
  'ar',
  'az',
  'bn',
  'bg',
  'ca',
  'zh_CN',
  'zh_HK',
  'zh_TW',
  'hr',
  'cs',
  'da',
  'nl',
  'en',
  'en_GB',
  'en_US',
  'et',
  'fil',
  'fi',
  'fr',
  'ka',
  'de',
  'el',
  'gu',
  'ha',
  'he',
  'hi',
  'hu',
  'id',
  'ga',
  'it',
  'ja',
  'kn',
  'kk',
  'rw_RW',
  'ko',
  'ky_KG',
  'lo',
  'lv',
  'lt',
  'mk',
  'ms',
  'ml',
  'mr',
  'nb',
  'fa',
  'pl',
  'pt_BR',
  'pt_PT',
  'pa',
  'ro',
  'ru',
  'sr',
  'sk',
  'sl',
  'es',
  'es_AR',
  'es_CL',
  'es_CO',
  'es_CR',
  'es_DO',
  'es_EC',
  'es_HN',
  'es_MX',
  'es_PA',
  'es_PE',
  'es_ES',
  'es_UY',
  'sw',
  'sv',
  'ta',
  'te',
  'th',
  'tr',
  'uk',
  'ur',
  'uz',
  'vi',
  'zu',
];

const STORAGE_KEY = 'whatsapp_template_language';

const upperFirst = text => text.charAt(0).toUpperCase() + text.slice(1);

// "Español (Ecuador)", the way Meta lists a language; the name is written in the language of the screen.
export const languageLabel = (code, uiLocale = 'es') => {
  if (!code) return '—';
  const locale = code.replace('_', '-');
  try {
    const name = new Intl.DisplayNames([uiLocale.replace('_', '-')], {
      type: 'language',
      languageDisplay: 'dialect',
    }).of(locale);
    return name ? upperFirst(name) : code;
  } catch {
    return code;
  }
};

export const languageOptions = (uiLocale = 'es') =>
  META_LANGUAGES.map(code => ({
    value: code,
    label: languageLabel(code, uiLocale),
  })).sort((first, second) => first.label.localeCompare(second.label));

// What a new template starts in: the language used last, else the account's language when Meta supports it, else Spanish.
export const defaultLanguage = accountLocale => {
  try {
    const remembered = window.localStorage.getItem(STORAGE_KEY);
    if (META_LANGUAGES.includes(remembered)) return remembered;
  } catch {
    // no storage: fall through
  }
  const own = String(accountLocale || '').replace('-', '_');
  if (META_LANGUAGES.includes(own)) return own;
  return 'es';
};

export const rememberLanguage = code => {
  try {
    window.localStorage.setItem(STORAGE_KEY, code);
  } catch {
    // no storage: nothing to remember
  }
};
