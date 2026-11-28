import { shallowMount, flushPromises } from '@vue/test-utils';
import { ref } from 'vue';
import LocaleList from './LocaleList.vue';
import LocaleCard from '../../LocaleCard/LocaleCard.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';

const { dispatch, updateUISettings, useTrack } = vi.hoisted(() => ({
  dispatch: vi.fn(),
  updateUISettings: vi.fn(),
  useTrack: vi.fn(),
}));
vi.mock('dashboard/composables/store', () => ({
  useStore: () => ({ dispatch }),
}));
vi.mock('dashboard/composables', () => ({ useAlert: vi.fn(), useTrack }));
vi.mock('dashboard/composables/useUISettings', () => ({
  useUISettings: () => ({
    uiSettings: ref({ last_active_locale_code: 'es' }),
    updateUISettings,
  }),
}));
vi.mock('vue-i18n', () => ({ useI18n: () => ({ t: key => key }) }));
vi.mock('vue-router', () => ({
  useRoute: () => ({ name: 'portal_locales_index' }),
}));

describe('remove portal locale', () => {
  it.each([true, false])(
    'requires confirmation and updates the active locale only on success: %s',
    async success => {
      if (success) dispatch.mockResolvedValue({});
      else dispatch.mockRejectedValue(new Error('Cannot remove locale'));
      const wrapper = shallowMount(LocaleList, {
        props: {
          locales: [{ code: 'es', name: 'Español', isDraft: true }],
          portal: { slug: 'docs', meta: { default_locale: 'en' } },
        },
        global: {
          stubs: {
            Dialog: { methods: { open() {}, close() {} }, template: '<div />' },
          },
        },
      });
      wrapper.getComponent(LocaleCard).vm.$emit('action', { action: 'delete' });
      await wrapper.vm.$nextTick();
      expect(dispatch).not.toHaveBeenCalled();
      wrapper.getComponent(Dialog).vm.$emit('confirm');
      await flushPromises();
      expect(dispatch).toHaveBeenCalledWith('portals/removeLocale', {
        portalSlug: 'docs',
        locale: 'es',
      });
      if (success) {
        expect(updateUISettings).toHaveBeenCalledWith({
          last_active_locale_code: 'en',
        });
        expect(useTrack).toHaveBeenCalled();
      } else {
        expect(updateUISettings).not.toHaveBeenCalled();
        expect(useTrack).not.toHaveBeenCalled();
      }
      wrapper.unmount();
    }
  );
});
