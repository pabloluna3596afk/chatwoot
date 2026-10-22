<script setup>
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import Checkbox from 'dashboard/components-next/checkbox/Checkbox.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import {
  useStoreGetters,
  useFunctionGetter,
} from 'dashboard/composables/store';
import { useAccount } from 'dashboard/composables/useAccount';
import { FEATURE_FLAGS } from 'dashboard/featureFlags';
import {
  useUISettings,
  DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER,
  SIDEBAR_SECTION_ATTRIBUTE_TYPE,
  attributeCategorySlug,
  SYSTEM_CATEGORY_SLUG,
} from 'dashboard/composables/useUISettings';

const { t } = useI18n();
const getters = useStoreGetters();
const { isCloudFeatureEnabled } = useAccount();
const {
  uiSettings,
  updateUISettings,
  conversationSidebarItemsOrder,
  conversationSidebarVisibleItems,
  isConversationSidebarItemVisible,
  toggleConversationSidebarItemVisibility,
  resetConversationSidebarVisibility,
  isConversationSidebarCategoryVisible,
  toggleConversationSidebarCategoryVisibility,
  reorderConversationSidebarCategories,
  conversationSidebarCategoryOrder,
  setConversationSidebarItemsOrder,
} = useUISettings();

const shopifyIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'shopify'
);
const linearIntegration = useFunctionGetter(
  'integrations/getIntegration',
  'linear'
);

const isSectionAvailable = name => {
  if (name === 'shopify_orders') {
    return !!shopifyIntegration.value?.enabled;
  }
  if (name === 'linear_issues') {
    return (
      isCloudFeatureEnabled(FEATURE_FLAGS.LINEAR) &&
      !!linearIntegration.value?.id
    );
  }
  if (name === 'calendar_events') {
    return isCloudFeatureEnabled(FEATURE_FLAGS.CALENDAR);
  }
  return true;
};

const SIDEBAR_MENU_MAX_HEIGHT = 640;
const isOpen = ref(false);
const collapsedSections = computed(
  () => uiSettings.value.conversation_sidebar_menu_collapsed_sections || []
);
const toggleCategories = name => {
  const collapsed = new Set(collapsedSections.value);
  if (collapsed.has(name)) collapsed.delete(name);
  else collapsed.add(name);
  updateUISettings({
    conversation_sidebar_menu_collapsed_sections: [...collapsed],
  });
};
const dragging = ref(false);
const sections = ref([]);
/** Local category lists keyed by section name (mutated by Draggable). */
const categoryRows = ref({});

const attributesByType = attributeType =>
  getters['attributes/getAttributesByModel'].value(attributeType) || [];

const buildCategoriesForType = attributeType => {
  const groups = new Map();
  attributesByType(attributeType).forEach(attribute => {
    const label = (attribute?.category || '').trim();
    const slug = attributeCategorySlug(label);
    const key = label || '__uncategorized__';
    if (!groups.has(key)) {
      groups.set(key, {
        key,
        slug,
        title: label || t('CUSTOM_ATTRIBUTES.UNCATEGORIZED'),
      });
    }
  });

  const list = [...groups.values()];

  // Conversation metadata (browser, IP, â€¦) always exposed as System under info.
  if (attributeType === 'conversation_attribute') {
    list.unshift({
      key: '__system__',
      slug: SYSTEM_CATEGORY_SLUG,
      title: t('CUSTOM_ATTRIBUTES.SYSTEM'),
    });
  }

  if (list.length <= 1) return [];

  const savedOrder = conversationSidebarCategoryOrder(attributeType);
  return list.sort((a, b) => {
    if (savedOrder.length) {
      const aPos = savedOrder.indexOf(a.slug);
      const bPos = savedOrder.indexOf(b.slug);
      if (aPos !== -1 || bPos !== -1) {
        if (aPos === -1) return 1;
        if (bPos === -1) return -1;
        return aPos - bPos;
      }
    }
    if (a.key === '__system__') return -1;
    if (b.key === '__system__') return 1;
    if (a.key === '__uncategorized__') return 1;
    if (b.key === '__uncategorized__') return -1;
    return a.title.localeCompare(b.title);
  });
};

const syncFromSettings = () => {
  if (dragging.value) return;
  sections.value = conversationSidebarItemsOrder.value
    .filter(item => isSectionAvailable(item.name))
    .map(item => ({
      ...item,
    }));
  const rows = {};
  Object.entries(SIDEBAR_SECTION_ATTRIBUTE_TYPE).forEach(
    ([sectionName, attributeType]) => {
      rows[sectionName] = buildCategoriesForType(attributeType);
    }
  );
  categoryRows.value = rows;
};

syncFromSettings();

const visibleCount = computed(
  () =>
    sections.value.filter(item =>
      conversationSidebarVisibleItems.value.includes(item.name)
    ).length
);

const sectionLabel = name => {
  const key = `CONVERSATION.SIDEBAR.MENU.${name}`;
  const translated = t(key);
  return translated === key ? name : translated;
};

const toggleMenu = () => {
  if (!isOpen.value) syncFromSettings();
  isOpen.value = !isOpen.value;
};

const onSectionDragEnd = () => {
  dragging.value = false;
  // Keep unavailable sections in saved order so prefs survive enabling an integration later.
  const availableNames = new Set(sections.value.map(item => item.name));
  const hidden = conversationSidebarItemsOrder.value.filter(
    item => !availableNames.has(item.name)
  );
  setConversationSidebarItemsOrder([
    ...sections.value.map(item => ({ ...item })),
    ...hidden,
  ]);
};

const onToggleSection = name => {
  toggleConversationSidebarItemVisibility(name);
};

const onToggleCategory = (sectionName, slug) => {
  const attributeType = SIDEBAR_SECTION_ATTRIBUTE_TYPE[sectionName];
  if (!attributeType) return;
  const allSlugs = (categoryRows.value[sectionName] || []).map(c => c.slug);
  toggleConversationSidebarCategoryVisibility(attributeType, slug, allSlugs);
};

const onCategoryDragEnd = sectionName => {
  dragging.value = false;
  const attributeType = SIDEBAR_SECTION_ATTRIBUTE_TYPE[sectionName];
  if (!attributeType) return;
  const order = (categoryRows.value[sectionName] || []).map(c => c.slug);
  reorderConversationSidebarCategories(attributeType, order);
};

const onReset = () => {
  resetConversationSidebarVisibility();
  sections.value = DEFAULT_CONVERSATION_SIDEBAR_ITEMS_ORDER.filter(item =>
    isSectionAvailable(item.name)
  ).map(item => ({
    ...item,
  }));
  const rows = {};
  Object.entries(SIDEBAR_SECTION_ATTRIBUTE_TYPE).forEach(
    ([sectionName, attributeType]) => {
      rows[sectionName] = buildCategoriesForType(attributeType);
    }
  );
  categoryRows.value = rows;
};
</script>

<template>
  <MenuPopover
    v-model:open="isOpen"
    :dismissible="!dragging"
    :label="$t('CONVERSATION.SIDEBAR.MENU.TITLE')"
    panel-class="w-80 max-w-[calc(100vw-2rem)] !pt-0 [&>div]:!px-0 [&>div]:!pb-0"
    :max-height="SIDEBAR_MENU_MAX_HEIGHT"
  >
    <template #trigger>
      <Button
        v-tooltip="$t('CONVERSATION.SIDEBAR.MENU.TITLE')"
        icon="i-lucide-ellipsis-vertical"
        ghost
        sm
        slate
        :class="isOpen ? 'bg-n-alpha-2' : ''"
        @click.stop="toggleMenu"
      />
    </template>
    <template #content>
      <div class="flex flex-col min-h-0 pb-2">
        <div class="shrink-0 px-3 pt-3 pb-2">
          <div class="flex items-center justify-between gap-2">
            <p class="mb-0 text-sm font-medium text-n-slate-12">
              {{ $t('CONVERSATION.SIDEBAR.MENU.TITLE') }}
            </p>
            <Button
              icon="i-lucide-rotate-ccw"
              ghost
              xs
              slate
              :title="$t('CONVERSATION.SIDEBAR.MENU.RESET')"
              :aria-label="$t('CONVERSATION.SIDEBAR.MENU.RESET')"
              @click="onReset"
            />
          </div>
          <p class="mb-0 text-xs text-n-slate-11 whitespace-nowrap">
            {{
              $t('CONVERSATION.SIDEBAR.MENU.VISIBLE_COUNT', {
                count: visibleCount,
              })
            }}
            <!-- eslint-disable-next-line vue/no-bare-strings-in-template -->
            · {{ $t('CONVERSATION.SIDEBAR.MENU.ORDER_HINT') }}
          </p>
        </div>

        <Draggable
          v-model="sections"
          animation="200"
          ghost-class="opacity-50"
          handle=".section-drag-handle"
          item-key="name"
          class="max-h-[min(60vh,32rem)] overflow-y-auto min-h-0 px-2 [scrollbar-width:thin] [&::-webkit-scrollbar-button]:hidden"
          @start="dragging = true"
          @end="onSectionDragEnd"
        >
          <template #item="{ element }">
            <div>
              <div
                class="group flex items-center gap-2 h-8 px-2 rounded-md hover:bg-n-alpha-2"
              >
                <span
                  class="section-drag-handle i-lucide-grip-vertical size-3.5 shrink-0 text-n-slate-9 cursor-grab"
                />
                <label
                  class="flex flex-1 items-center gap-2 min-w-0 mb-0 cursor-pointer"
                >
                  <Checkbox
                    class="shrink-0"
                    :model-value="
                      isConversationSidebarItemVisible(element.name)
                    "
                    @change="onToggleSection(element.name)"
                  />
                  <span
                    class="text-sm leading-4 text-n-slate-12 line-clamp-2 break-words"
                  >
                    {{ sectionLabel(element.name) }}
                  </span>
                </label>
                <Button
                  v-if="categoryRows[element.name]?.length"
                  :icon="
                    collapsedSections.includes(element.name)
                      ? 'i-lucide-chevron-right'
                      : 'i-lucide-chevron-down'
                  "
                  ghost
                  xs
                  slate
                  class="shrink-0 [&_span]:!size-3.5"
                  :aria-label="
                    $t('CONVERSATION.SIDEBAR.MENU.CATEGORIES_FOR', {
                      section: sectionLabel(element.name),
                    })
                  "
                  :aria-expanded="!collapsedSections.includes(element.name)"
                  @click="toggleCategories(element.name)"
                />
              </div>

              <Draggable
                v-if="
                  isConversationSidebarItemVisible(element.name) &&
                  categoryRows[element.name]?.length &&
                  !collapsedSections.includes(element.name)
                "
                :list="categoryRows[element.name]"
                animation="200"
                ghost-class="opacity-50"
                handle=".category-drag-handle"
                item-key="slug"
                class="ps-6"
                @start="dragging = true"
                @end="onCategoryDragEnd(element.name)"
              >
                <template #item="{ element: category }">
                  <div
                    class="group flex items-center gap-2 h-7 px-2 rounded-md text-xs text-n-slate-11 hover:bg-n-alpha-2"
                  >
                    <span
                      class="category-drag-handle i-lucide-grip-vertical size-3.5 shrink-0 text-n-slate-9 cursor-grab"
                    />
                    <label
                      class="flex flex-1 items-center gap-2 min-w-0 mb-0 cursor-pointer"
                    >
                      <Checkbox
                        class="shrink-0"
                        :model-value="
                          isConversationSidebarCategoryVisible(
                            SIDEBAR_SECTION_ATTRIBUTE_TYPE[element.name],
                            category.slug
                          )
                        "
                        @change="onToggleCategory(element.name, category.slug)"
                      />
                      <span
                        class="text-xs leading-[0.875rem] text-n-slate-11 line-clamp-2 break-words"
                      >
                        {{ category.title }}
                      </span>
                    </label>
                  </div>
                </template>
              </Draggable>
            </div>
          </template>
        </Draggable>

        <p
          v-if="!visibleCount"
          class="shrink-0 mb-0 px-3 py-2 text-xs text-n-slate-11"
        >
          {{ $t('CONVERSATION.SIDEBAR.MENU.EMPTY') }}
        </p>
      </div>
    </template>
  </MenuPopover>
</template>
