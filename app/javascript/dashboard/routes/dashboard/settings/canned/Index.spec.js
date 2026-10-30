import { shallowMount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import { describe, expect, it, vi } from 'vitest';
import cannedMgmtEn from 'dashboard/i18n/locale/en/cannedMgmt.json';
import cannedMgmtEs from 'dashboard/i18n/locale/es/cannedMgmt.json';
import Index from './Index.vue';
import ToolCards from 'dashboard/components-next/ToolList/ToolCards.vue';

vi.mock('dashboard/composables', () => ({ useAlert: vi.fn() }));
vi.mock('dashboard/composables/useAdmin', () => ({
  useAdmin: () => ({ isAdmin: { value: true } }),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch: vi.fn() }),
  useStoreGetters: () => ({
    getSortedCannedResponses: {
      value: () => [
        {
          id: 1,
          short_code: 'greeting',
          content: '{{ contact.name }} {{ conversation.inbox_name }}',
          category: 'Support',
          visibility: 'personal',
          approval_status: 'approved',
          created_by_id: 3,
        },
      ],
    },
    getUIFlags: { value: { fetchingList: false } },
  }),
  useMapGetter: key =>
    ({
      getCurrentUser: { value: { id: 3 } },
      getCurrentAccount: { value: { locale: 'es' } },
      'attributes/getAttributes': {
        value: [{ attribute_key: 'plan', attribute_display_name: 'Plan' }],
      },
    })[key],
}));

describe('canned response settings', () => {
  it('passes account-locale labels and custom attributes to the card wall', () => {
    const i18n = createI18n({
      legacy: false,
      locale: 'es',
      messages: { en: cannedMgmtEn, es: cannedMgmtEs },
    });
    const wrapper = shallowMount(Index, {
      global: {
        plugins: [i18n],
        stubs: {
          SettingsLayout: {
            template: '<div><slot name="header"/><slot name="body"/></div>',
          },
          ToolCards: false,
        },
      },
    });
    const labels = wrapper.findComponent(ToolCards).props('variableLabels');

    expect(labels['contact.name']).toBe('Nombre del contacto');
    expect(labels['conversation.inbox_name']).toBe(
      'Bandeja de la conversación'
    );
    expect(labels['account.name']).toBe('Nombre de la cuenta');
    expect(labels["contact.custom_attribute['plan']"]).toBe('Plan');
    wrapper.unmount();
  });
});
