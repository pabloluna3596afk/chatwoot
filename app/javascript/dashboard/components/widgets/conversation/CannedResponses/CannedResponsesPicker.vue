<script setup>
import { resolvePreviewText } from 'dashboard/helper/shortcutPreview';
import ShortcutPreview from 'dashboard/components-next/preview-picker/ShortcutPreview.vue';
import SearchInput from 'dashboard/components-next/input/SearchInput.vue';
import { ref, computed, onMounted, useTemplateRef } from 'vue';
import { useI18n } from 'vue-i18n';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import { picoSearch } from '@chatwoot/pico-search';

const props = defineProps({ variables: { type: Object, default: () => ({}) } });
const emit = defineEmits(['onSelect']);
const { t } = useI18n();
const selectedResponse = ref(null);
const resolveContent = content =>
  resolvePreviewText(
    content,
    props.variables,
    t('CONVERSATION.PICKER.PREVIEW.MISSING')
  );

const store = useStore();
const { getPlainText } = useMessageFormatter();

const query = ref('');
const selectedCategory = ref(null);
const searchInput = useTemplateRef('searchInput');

const cannedResponses = useMapGetter('getCannedResponses');

onMounted(() => {
  searchInput.value.$el.querySelector('input').focus({ preventScroll: true });
  store.dispatch('getCannedResponse', { usable: true });
});

const categories = computed(() => {
  const set = new Set();
  (cannedResponses.value || []).forEach(item => {
    if (item.category) set.add(item.category);
  });
  return [...set].sort((a, b) => a.localeCompare(b));
});

const categoryFiltered = computed(() => {
  const list = cannedResponses.value || [];
  if (selectedCategory.value === null) return list;
  if (selectedCategory.value === '') {
    return list.filter(item => !item.category);
  }
  return list.filter(item => item.category === selectedCategory.value);
});

const filteredResponses = computed(() => {
  const q = query.value.trim();
  if (!q) return categoryFiltered.value;
  return picoSearch(categoryFiltered.value, q, [
    { name: 'short_code', weight: 4 },
    { name: 'category', weight: 2 },
    'content',
  ]);
});

const previewResponse = computed(() =>
  filteredResponses.value.includes(selectedResponse.value)
    ? selectedResponse.value
    : filteredResponses.value[0]
);

const chipClass = active =>
  active
    ? 'bg-n-slate-5 text-n-slate-12 border-n-brand'
    : 'bg-n-alpha-black2 text-n-slate-12 border-n-weak hover:bg-n-alpha-2';

const previewContent = content => {
  const plain = getPlainText(resolveContent(content));
  return plain.length > 160 ? `${plain.slice(0, 160)}…` : plain;
};
</script>

<template>
  <div class="flex flex-col min-h-0 min-w-0 w-full">
    <SearchInput
      ref="searchInput"
      v-model="query"
      :placeholder="t('CANNED_MGMT.PICKER.SEARCH_PLACEHOLDER')"
      class="shrink-0 mb-2.5 [&_input]:min-h-11 [&_input]:text-base sm:[&_input]:min-h-0 sm:[&_input]:text-sm"
      size="sm"
    />

    <div
      v-if="categories.length || (cannedResponses || []).some(r => !r.category)"
      class="flex shrink-0 gap-2 mb-2.5 overflow-x-auto"
      @mousedown.prevent
    >
      <button
        type="button"
        class="min-h-11 sm:min-h-0 shrink-0 max-w-full break-words px-2.5 py-1 text-xs rounded-lg border border-solid transition-colors"
        :class="chipClass(selectedCategory === null)"
        @click="selectedCategory = null"
      >
        {{ t('CANNED_MGMT.PICKER.ALL_CATEGORIES') }}
      </button>
      <button
        v-for="cat in categories"
        :key="cat"
        type="button"
        class="min-h-11 sm:min-h-0 shrink-0 max-w-full break-words px-2.5 py-1 text-xs rounded-lg border border-solid transition-colors"
        :class="chipClass(selectedCategory === cat)"
        @click="selectedCategory = cat"
      >
        {{ cat }}
      </button>
      <button
        v-if="(cannedResponses || []).some(r => !r.category)"
        type="button"
        class="min-h-11 sm:min-h-0 shrink-0 max-w-full break-words px-2.5 py-1 text-xs rounded-lg border border-solid transition-colors"
        :class="chipClass(selectedCategory === '')"
        @click="selectedCategory = ''"
      >
        {{ t('CANNED_MGMT.PICKER.UNCATEGORIZED') }}
      </button>
    </div>

    <div class="flex min-h-0 min-w-0 flex-col sm:flex-row gap-3">
      <div
        class="flex-1 min-w-0 bg-n-background outline-n-container outline outline-1 rounded-lg min-h-0 max-h-[18.75rem] overflow-y-auto overscroll-contain p-2.5"
      >
        <div
          v-for="(item, i) in filteredResponses"
          :key="item.id || item.short_code"
        >
          <button
            type="button"
            class="block min-h-11 break-words p-2.5 w-full text-start rounded-lg cursor-pointer hover:bg-n-alpha-2 dark:hover:bg-n-solid-2"
            @mousedown.prevent
            @focus="selectedResponse = item"
            @mouseenter="selectedResponse = item"
            @click="emit('onSelect', item)"
          >
            <div
              class="flex flex-wrap justify-between items-center gap-2 mb-1.5"
            >
              <p
                class="min-w-0 max-w-full mb-0 text-sm font-medium text-n-slate-12"
              >
                /{{ item.short_code }}
              </p>
              <div class="flex flex-wrap min-w-0 gap-1 items-center">
                <span
                  v-if="item.category"
                  class="inline-block max-w-full break-words px-2 py-1 text-xs leading-none rounded-lg bg-n-slate-3 text-n-slate-12"
                >
                  {{ item.category }}
                </span>
                <span
                  class="inline-block max-w-full break-words px-2 py-1 text-xs leading-none rounded-lg bg-n-alpha-black2 text-n-slate-11"
                >
                  {{
                    item.visibility === 'personal'
                      ? t('CANNED_MGMT.PICKER.PERSONAL_BADGE')
                      : t('CANNED_MGMT.PICKER.ACCOUNT_BADGE')
                  }}
                </span>
              </div>
            </div>
            <p class="mb-0 text-sm text-n-slate-11 truncate">
              {{ previewContent(item.content) }}
            </p>
          </button>
          <hr
            v-if="i !== filteredResponses.length - 1"
            :key="`hr-${i}`"
            class="border-b border-solid border-n-weak my-2.5 mx-auto max-w-[95%]"
          />
        </div>
        <div v-if="!filteredResponses.length" class="py-8 text-center">
          <div v-if="query && (cannedResponses || []).length">
            <p class="mb-0 text-n-slate-11">
              {{ t('CANNED_MGMT.PICKER.NO_RESULTS') }}
              <strong>{{ query }}</strong>
            </p>
          </div>
          <p v-else class="mb-0 text-n-slate-11">
            {{ t('CANNED_MGMT.PICKER.EMPTY_PENDING_HINT') }}
          </p>
        </div>
      </div>
      <ShortcutPreview
        v-if="previewResponse"
        :content="resolveContent(previewResponse.content)"
        class="flex-1 min-h-0 max-h-[18.75rem] overflow-y-auto p-2.5"
      />
    </div>
  </div>
</template>
