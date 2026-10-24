<script setup>
import { computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute, useRouter } from 'vue-router';
import { useMapGetter, useStore } from 'dashboard/composables/store.js';
import { buildPortalURL } from 'dashboard/helper/portalHelper';

import Button from 'dashboard/components-next/button/Button.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';

const emit = defineEmits(['close', 'createPortal']);

const { t } = useI18n();
const route = useRoute();
const router = useRouter();
const store = useStore();

const DEFAULT_ROUTE = 'portals_articles_index';
const CATEGORY_ROUTE = 'portals_categories_index';
const CATEGORY_SUB_ROUTES = [
  'portals_categories_articles_index',
  'portals_categories_articles_new',
  'portals_categories_articles_edit',
];

const portals = useMapGetter('portals/allPortals');

const currentPortalSlug = computed(() => route.params.portalSlug);

const portalLink = computed(() => {
  return buildPortalURL(currentPortalSlug.value);
});

const isPortalActive = portal => {
  return portal.slug === currentPortalSlug.value;
};

const getPortalThumbnailSrc = portal => {
  return portal?.logo?.file_url || '';
};

const menuItems = computed(() =>
  portals.value.map(portal => ({
    label: portal.name,
    title: [portal.name, portal.custom_domain].filter(Boolean).join(' - '),
    portal,
    isSelected: isPortalActive(portal),
    thumbnail: { name: portal.name, src: getPortalThumbnailSrc(portal) },
  }))
);

const fetchPortalAndItsCategories = async (slug, locale) => {
  await store.dispatch('portals/switchPortal', true);
  await store.dispatch('portals/index');
  const selectedPortalParam = {
    portalSlug: slug,
    locale,
  };
  await store.dispatch('portals/show', selectedPortalParam);
  await store.dispatch('categories/index', selectedPortalParam);
  await store.dispatch('agents/get');
  await store.dispatch('portals/switchPortal', false);
};

const handlePortalChange = async portal => {
  if (isPortalActive(portal)) return;
  const {
    slug,
    meta: { default_locale: defaultLocale },
  } = portal;
  emit('close');
  await fetchPortalAndItsCategories(slug, defaultLocale);
  const targetRouteName = CATEGORY_SUB_ROUTES.includes(route.name)
    ? CATEGORY_ROUTE
    : route.name || DEFAULT_ROUTE;
  router.push({
    name: targetRouteName,
    params: {
      portalSlug: slug,
      locale: defaultLocale,
    },
  });
};

const openCreatePortalDialog = () => {
  emit('createPortal');
  emit('close');
};

const onClickPreviewPortal = () => {
  window.open(portalLink.value, '_blank');
};

const redirectToPortalHomePage = () => {
  router.push({
    name: 'portals_index',
    params: {
      navigationPath: DEFAULT_ROUTE,
    },
  });
};
</script>

<template>
  <MenuPopover
    :menu-items="menuItems"
    :label="t('HELP_CENTER.PORTAL_SWITCHER.PORTALS')"
    show-search
    align="start"
    panel-class="w-[27.5rem] max-w-[calc(100vw-2rem)] max-sm:[&_button]:min-h-11"
    @action="handlePortalChange($event.portal)"
  >
    <template #trigger="{ open, toggle }">
      <slot name="trigger" :open="open" :toggle="toggle">
        <Button
          icon="i-lucide-chevron-down"
          :aria-label="t('HELP_CENTER.PORTAL_SWITCHER.PORTALS')"
          :aria-expanded="open"
          aria-haspopup="dialog"
          color="slate"
          variant="ghost"
          class="min-h-11 min-w-11 sm:min-h-0 sm:min-w-0"
          @click="toggle"
        />
      </slot>
    </template>
    <template #label="{ item }">
      <span class="flex flex-col min-w-0 text-start">
        <span class="text-sm font-medium truncate">{{ item.label }}</span>
        <span
          v-if="item.portal.custom_domain"
          class="text-xs text-n-slate-11 truncate"
        >
          {{ item.portal.custom_domain }}
        </span>
      </span>
    </template>
    <template #footer="{ close }">
      <div class="flex flex-wrap gap-2 p-3 border-t border-n-weak">
        <Button
          :label="t('HELP_CENTER.PORTAL_SWITCHER.PORTALS')"
          color="slate"
          variant="ghost"
          class="min-h-11 sm:min-h-0"
          @click="
            close();
            redirectToPortalHomePage();
          "
        />
        <Button
          icon="i-lucide-arrow-up-right"
          :aria-label="t('HELP_CENTER.EDIT_HEADER.PREVIEW')"
          color="slate"
          variant="ghost"
          class="min-h-11 min-w-11 sm:min-h-0 sm:min-w-0"
          @click="onClickPreviewPortal"
        />
        <Button
          :label="t('HELP_CENTER.PORTAL_SWITCHER.NEW_PORTAL')"
          color="slate"
          icon="i-lucide-plus"
          class="w-full min-h-11 sm:min-h-0"
          @click="
            close(false);
            openCreatePortalDialog();
          "
        />
      </div>
    </template>
  </MenuPopover>
</template>
