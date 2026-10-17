import { flushPromises, mount } from '@vue/test-utils';
import { createI18n } from 'vue-i18n';
import en from 'dashboard/i18n/locale/en/onboarding.json';
import es from 'dashboard/i18n/locale/es/onboarding.json';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import WhatsappGuideDialog from '../../inbox-setup/WhatsappGuideDialog.vue';

describe('WhatsApp connection guide', () => {
  let wrapper;
  let i18n;
  const originalShowModal = HTMLDialogElement.prototype.showModal;
  const originalClose = HTMLDialogElement.prototype.close;

  beforeEach(() => {
    window.chatwootConfig = {};
    i18n = createI18n({ legacy: false, locale: 'es', messages: { en, es } });
    HTMLDialogElement.prototype.showModal = function open() {
      this.setAttribute('open', '');
    };
    HTMLDialogElement.prototype.close = function close() {
      this.removeAttribute('open');
    };
  });

  afterEach(() => {
    wrapper?.unmount();
    delete window.chatwootConfig;
    vi.restoreAllMocks();
    HTMLDialogElement.prototype.showModal = originalShowModal;
    HTMLDialogElement.prototype.close = originalClose;
  });

  it.each(['en', 'es'])(
    'opens the shared scrollable dialog with all verified details and official links in %s',
    async lang => {
      i18n.global.locale.value = lang;
      wrapper = mount(WhatsappGuideDialog, {
        global: {
          plugins: [i18n],
          stubs: { TeleportWithDirection: { template: '<div><slot /></div>' } },
        },
      });
      await flushPromises();
      const strings = { en, es }[lang].ONBOARDING_WHATSAPP.GUIDE;
      expect(wrapper.get('dialog').attributes()).toHaveProperty('open');
      expect(wrapper.getComponent(Dialog).props('bodyScroll')).toBe(true);
      expect(wrapper.get('h3').text()).toBe(strings.TITLE);
      expect(
        wrapper
          .get('[data-testid="guide-steps"]')
          .findAll('p')
          .map(step => step.text())
      ).toEqual(Object.values(strings.STEPS));
      expect(
        wrapper
          .get('[data-testid="guide-changes"]')
          .findAll('li')
          .map(change => change.text())
      ).toEqual(Object.values(strings.CHANGES));
      expect(wrapper.text()).toContain('6');
      expect(wrapper.text()).toContain('14');
      expect(wrapper.text()).toContain('30');
      expect(wrapper.text()).toContain('2.24.17');
      expect(wrapper.text()).toContain('20');
      const links = wrapper.findAll('a');
      expect(links.map(link => link.attributes('href'))).toEqual([
        'https://developers.facebook.com/documentation/business-messaging/whatsapp/embedded-signup/onboarding-business-app-users',
        'https://developers.facebook.com/documentation/business-messaging/whatsapp/solution-providers/get-started-for-tech-providers',
      ]);
      links.forEach(link => {
        expect(link.attributes('target')).toBe('_blank');
        expect(link.attributes('rel').split(' ')).toContain('noopener');
      });
      expect(wrapper.get('button').text()).toBe(strings.CLOSE);
      await wrapper.get('button').trigger('click');
      expect(wrapper.emitted('close')).toHaveLength(1);
    }
  );

  it.each([undefined, '', 'https://example.com/guide.mp4'])(
    'only renders the video section with a configured URL: %s',
    async url => {
      window.chatwootConfig.whatsappGuideVideoUrl = url;
      wrapper = mount(WhatsappGuideDialog, {
        global: {
          plugins: [i18n],
          stubs: {
            Dialog: { template: '<div><slot /></div>', methods: { open() {} } },
          },
        },
      });
      await flushPromises();
      expect(wrapper.find('[data-testid="guide-video"]').exists()).toBe(
        Boolean(url)
      );
      if (url) {
        expect(wrapper.get('video').attributes('src')).toBe(url);
        expect(wrapper.get('video').attributes('preload')).toBe('none');
        expect(wrapper.get('video').attributes()).toHaveProperty('controls');
      }
    }
  );

  it.each([false, true])(
    'supports a video slot only when a URL is configured: %s',
    configured => {
      if (configured)
        window.chatwootConfig.whatsappGuideVideoUrl =
          'https://example.com/guide.mp4';
      wrapper = mount(WhatsappGuideDialog, {
        global: {
          plugins: [i18n],
          stubs: {
            Dialog: { template: '<div><slot /></div>', methods: { open() {} } },
          },
        },
        slots: {
          video:
            '<template #video="{ url }"><a data-testid="custom-video" :href="url">Video</a></template>',
        },
      });
      expect(wrapper.find('[data-testid="custom-video"]').exists()).toBe(
        configured
      );
      expect(wrapper.find('video').exists()).toBe(false);
      if (configured)
        expect(
          wrapper.get('[data-testid="custom-video"]').attributes('href')
        ).toBe(window.chatwootConfig.whatsappGuideVideoUrl);
    }
  );

  it.each([undefined, false, 'false', true])(
    'only displays the unchanged light and dark provider badges for a boolean true flag: %s',
    flag => {
      window.chatwootConfig.metaTechProviderLive = flag;
      wrapper = mount(WhatsappGuideDialog, {
        global: {
          plugins: [i18n],
          stubs: {
            Dialog: { template: '<div><slot /></div>', methods: { open() {} } },
          },
        },
      });
      expect(wrapper.find('[data-testid="meta-tech-provider"]').exists()).toBe(
        flag === true
      );
      if (flag === true) {
        const images = wrapper
          .get('[data-testid="meta-tech-provider"]')
          .findAll('img');
        expect(images).toHaveLength(2);
        expect(images[0].attributes('src')).toContain(
          'meta_tech_provider_black.svg'
        );
        expect(images[1].attributes('src')).toContain(
          'meta_tech_provider_white.svg'
        );
        images.forEach(img =>
          expect(img.classes()).toEqual(
            expect.arrayContaining(['h-auto', 'w-40'])
          )
        );
        expect(images[0].classes()).toContain('dark:hidden');
        expect(images[1].classes()).toContain('dark:block');
      }
    }
  );
});
