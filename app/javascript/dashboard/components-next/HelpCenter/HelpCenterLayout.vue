<script setup>
import { ref, computed } from 'vue';
import { useI18n } from 'vue-i18n';
import { useRoute } from 'vue-router';
import { useMapGetter } from 'dashboard/composables/store.js';

import PaginationFooter from 'dashboard/components-next/pagination/PaginationFooter.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import PortalSwitcher from 'dashboard/components-next/HelpCenter/PortalSwitcher/PortalSwitcher.vue';
import CreatePortalDialog from 'dashboard/components-next/HelpCenter/PortalSwitcher/CreatePortalDialog.vue';

defineProps({
  currentPage: {
    type: Number,
    default: 1,
  },
  totalItems: {
    type: Number,
    default: 100,
  },
  itemsPerPage: {
    type: Number,
    default: 25,
  },
  showHeaderTitle: {
    type: Boolean,
    default: true,
  },
  showPaginationFooter: {
    type: Boolean,
    default: true,
  },
  breadcrumbLabel: {
    type: String,
    default: '',
  },
});

const emit = defineEmits(['update:currentPage']);

const route = useRoute();

const createPortalDialogRef = ref(null);

const { t } = useI18n();

const portals = useMapGetter('portals/allPortals');

const currentPortalSlug = computed(() => route.params.portalSlug);

const activePortal = computed(() =>
  portals.value?.find(portal => portal.slug === currentPortalSlug.value)
);

const activePortalName = computed(() => activePortal.value?.name);

const updateCurrentPage = page => {
  emit('update:currentPage', page);
};
</script>

<template>
  <section class="flex flex-col w-full h-full overflow-hidden bg-n-surface-1">
    <header class="sticky top-0 z-10 px-6 pb-3">
      <div class="w-full max-w-5xl mx-auto">
        <div
          v-if="showHeaderTitle"
          class="flex items-center justify-start h-20 gap-2"
        >
          <nav v-if="activePortalName" class="flex items-center min-w-0 gap-3">
            <div class="flex items-center min-w-0 gap-1.5">
              <span class="text-lg font-medium truncate text-n-slate-12">
                {{ activePortalName }}
              </span>
              <div class="relative shrink-0 group">
                <PortalSwitcher
                  @create-portal="createPortalDialogRef.dialogRef.open()"
                >
                  <template #trigger="{ open, toggle }">
                    <Button
                      icon="i-lucide-chevron-down"
                      :aria-label="t('HELP_CENTER.PORTAL_SWITCHER.PORTALS')"
                      :aria-expanded="open"
                      aria-haspopup="dialog"
                      :variant="open ? 'faded' : 'ghost'"
                      slate
                      xs
                      class="rounded-md min-h-11 min-w-11 sm:min-h-0 sm:min-w-0"
                      @click="toggle"
                    />
                  </template>
                </PortalSwitcher>
                <CreatePortalDialog ref="createPortalDialogRef" />
              </div>
            </div>

            <template v-if="breadcrumbLabel">
              <div class="w-0.5 h-4 rounded-2xl bg-n-weak shrink-0" />
              <span class="pl-1.5 text-lg font-medium truncate text-n-slate-12">
                {{ breadcrumbLabel }}
              </span>
            </template>
          </nav>
          <div class="flex justify-end min-w-0 grow">
            <slot name="title-actions" />
          </div>
        </div>
        <slot name="header-actions" />
      </div>
    </header>
    <main class="flex-1 px-6 overflow-y-auto">
      <div class="w-full max-w-5xl mx-auto py-3">
        <slot name="content" />
      </div>
    </main>
    <footer v-if="showPaginationFooter" class="sticky bottom-0 z-10">
      <PaginationFooter
        :current-page="currentPage"
        :total-items="totalItems"
        :items-per-page="itemsPerPage"
        class="max-w-[67rem]"
        @update:current-page="updateCurrentPage"
      />
    </footer>
    <!-- Do not remove this slot. It can be used to add dialogs. -->
    <slot />
  </section>
</template>
