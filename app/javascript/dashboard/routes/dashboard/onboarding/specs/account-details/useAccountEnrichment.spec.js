import { defineComponent, h, ref, reactive, nextTick } from 'vue';
import { createStore } from 'vuex';
import { mount } from '@vue/test-utils';
import { useRoute } from 'vue-router';
import { useAccountEnrichment } from '../../account-details/useAccountEnrichment';

vi.mock('vue-router');

// Mounts the composable against a real store and the real useAccount
// (only useRoute and the underlying account getter are faked),
// so a change to how those resolve their data is exercised here too. `presets`
// seeds form fields as if the user had already typed them.
const mountComposable = ({ account = {}, presets = {} } = {}) => {
  const store = createStore({
    modules: {
      accounts: {
        namespaced: true,
        getters: { getAccount: () => () => account },
      },
    },
  });

  const fields = {
    locale: ref(presets.locale || ''),
    website: ref(presets.website || ''),
    timezone: ref(presets.timezone || ''),
    name: ref(presets.name || ''),
    businessType: ref(presets.businessType || ''),
    country: ref(presets.country || ''),
  };

  let api;
  const Component = defineComponent({
    setup() {
      api = useAccountEnrichment(fields);
      return () => h('div');
    },
  });
  const wrapper = mount(Component, { global: { plugins: [store] } });
  return { ...api, fields, wrapper };
};

beforeEach(() => {
  useRoute.mockReturnValue({ params: { accountId: '1' } });
});

describe('useAccountEnrichment', () => {
  describe('populateFormFields', () => {
    it('does not send the Latin America locale region as a country', () => {
      const timezone = vi
        .spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions')
        .mockReturnValue({ timeZone: 'UTC' });
      const language = vi
        .spyOn(navigator, 'language', 'get')
        .mockReturnValue('es-419');
      const { fields, wrapper } = mountComposable();
      expect(fields.country.value).toBe('');
      expect(fields.locale.value).toBe('es');
      wrapper.unmount();
      timezone.mockRestore();
      language.mockRestore();
    });
    it('infers the country from the browser timezone and the supported browser language', () => {
      const timezone = vi
        .spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions')
        .mockReturnValue({ timeZone: 'America/Guayaquil' });
      const language = vi
        .spyOn(navigator, 'language', 'get')
        .mockReturnValue('es-EC');
      const { fields, wrapper } = mountComposable();
      expect(fields.country.value).toBe('EC');
      expect(fields.locale.value).toBe('es');
      expect(fields.timezone.value).toBe('America/Guayaquil');
      wrapper.unmount();
      timezone.mockRestore();
      language.mockRestore();
    });

    it('leaves missing detection empty so the UI can show its selectors', () => {
      const timezone = vi
        .spyOn(Intl.DateTimeFormat.prototype, 'resolvedOptions')
        .mockReturnValue({ timeZone: '' });
      const language = vi
        .spyOn(navigator, 'language', 'get')
        .mockReturnValue('de');
      const { fields, wrapper } = mountComposable();
      expect(fields.country.value).toBe('');
      expect(fields.locale.value).toBe('');
      expect(fields.timezone.value).toBe('');
      wrapper.unmount();
      timezone.mockRestore();
      language.mockRestore();
    });
    it('fills empty fields from the enriched attributes on mount', () => {
      const { fields } = mountComposable({
        account: {
          locale: 'en',
          name: 'Acme',
          custom_attributes: {
            website: 'https://acme.com',
            timezone: 'America/New_York',
            business_type: 'commerce',
            country: 'EC',
          },
        },
      });

      expect(fields.website.value).toBe('https://acme.com');
      expect(fields.timezone.value).toBe('America/New_York');
      expect(fields.name.value).toBe('Acme');
      expect(fields.businessType.value).toBe('commerce');
      expect(fields.country.value).toBe('EC');
    });

    it('falls back to brand_info for website', () => {
      const { fields } = mountComposable({
        account: {
          custom_attributes: {
            brand_info: {
              domain: 'acme.com',
            },
          },
        },
      });

      expect(fields.website.value).toBe('acme.com');
    });

    it('does not clobber fields the user already set', () => {
      const { fields } = mountComposable({
        presets: { website: 'mysite.com', name: 'My business' },
        account: {
          name: 'Enriched name',
          custom_attributes: {
            website: 'https://enriched.com',
          },
        },
      });

      expect(fields.website.value).toBe('mysite.com');
      expect(fields.name.value).toBe('My business');
    });

    it('prefers the account locale over the browser and uses a supported default', () => {
      const { fields } = mountComposable({ account: { locale: 'es' } });
      expect(fields.locale.value).toBe('es');
      const { fields: other } = mountComposable({
        account: { locale: 'de' },
      });
      expect(other.locale.value).toBe('en');
    });

    it('does not overwrite edits or a cleared website when enrichment arrives late', async () => {
      const account = reactive({
        name: 'Acme',
        custom_attributes: { website: 'acme.com' },
      });
      const { fields, getChangedFields } = mountComposable({ account });
      fields.name.value = 'My business';
      fields.website.value = '';
      account.name = 'Enriched name';
      account.custom_attributes = { website: 'enriched.com', country: 'EC' };
      await nextTick();

      expect(fields.name.value).toBe('My business');
      expect(fields.website.value).toBe('');
      expect(fields.country.value).toBe('EC');
      expect(getChangedFields()).toEqual(['website', 'name']);
    });
  });

  describe('isEnriching', () => {
    it('is true while the account is on the enrichment step', () => {
      const { isEnriching } = mountComposable({
        account: { custom_attributes: { onboarding_step: 'enrichment' } },
      });
      expect(isEnriching.value).toBe(true);
    });

    it('is false on any other step', () => {
      const { isEnriching } = mountComposable({
        account: { custom_attributes: { onboarding_step: 'account_details' } },
      });
      expect(isEnriching.value).toBe(false);
    });

    it('times out after 30s, flipping to false and populating', () => {
      vi.useFakeTimers();
      try {
        const { isEnriching, fields } = mountComposable({
          account: {
            custom_attributes: {
              onboarding_step: 'enrichment',
              business_type: 'other',
            },
          },
        });
        expect(isEnriching.value).toBe(true);

        vi.advanceTimersByTime(30000);

        expect(isEnriching.value).toBe(false);
        expect(fields.businessType.value).toBe('other');
      } finally {
        vi.useRealTimers();
      }
    });
  });

  describe('getChangedFields', () => {
    it('lists only enrichable fields edited after auto-fill', () => {
      const { fields, getChangedFields } = mountComposable({
        account: {
          custom_attributes: {
            website: 'https://acme.com',
          },
        },
      });

      expect(getChangedFields()).toEqual([]);

      fields.businessType.value = 'services';
      expect(getChangedFields()).toEqual(['business_type']);
    });
  });
});
