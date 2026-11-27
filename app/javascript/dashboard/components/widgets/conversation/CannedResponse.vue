<script setup>
import { computed, ref, onMounted, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { picoSearch } from '@chatwoot/pico-search';
import { useStore, useMapGetter } from 'dashboard/composables/store';
import { resolvePreviewText } from 'dashboard/helper/shortcutPreview';
import { escapeHtml } from 'shared/helpers/HTMLSanitizer';
import ShortcutPreview from 'dashboard/components-next/preview-picker/ShortcutPreview.vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';
import CaretAnchoredPicker from 'dashboard/components-next/preview-picker/CaretAnchoredPicker.vue';

const props = defineProps({
  focusSearch: { type: Boolean, default: true },
  caretPosition: {
    type: Object,
    default: null,
  },
  searchKey: {
    type: String,
    default: '',
  },
  variables: {
    type: Object,
    default: () => ({}),
  },
});

const emit = defineEmits(['replace', 'close', 'removeTrigger']);

// Characters kept before the match when a snippet has to skip ahead
const SNIPPET_LEAD = 24;
const HIGHLIGHT_CLASS = 'text-n-blue-text';

const store = useStore();
const { t } = useI18n();
const { getPlainText, highlightContent } = useMessageFormatter();

const cannedResponses = useMapGetter('getCannedResponses');
const uiFlags = useMapGetter('getUIFlags');
// The trigger can already be followed by text, from a draft or a caret moved back onto it
const searchQuery = ref(props.searchKey);

const searchTerm = computed(() => searchQuery.value.trim());

// An empty term makes `highlightContent`'s regex match at every position, wrapping the
// whole string in empty spans
const highlightMatches = text =>
  searchTerm.value
    ? highlightContent(escapeHtml(text), searchTerm.value, HIGHLIGHT_CLASS)
    : escapeHtml(text);

const buildSnippet = text => {
  const term = searchTerm.value;
  if (!term) return text;

  const index = text.toLowerCase().indexOf(term.toLowerCase());
  if (index <= SNIPPET_LEAD) return text;

  return `…${text.slice(index - SNIPPET_LEAD)}`;
};

const resolveContent = message =>
  resolvePreviewText(
    message,
    props.variables,
    t('CONVERSATION.PICKER.PREVIEW.MISSING')
  );

const records = computed(() =>
  cannedResponses.value.map(({ id, short_code: shortCode, content }) => {
    const resolved = resolveContent(content);
    return {
      id,
      content,
      resolved,
      shortCode,
      plainText: getPlainText(resolved).replace(/\s+/g, ' ').trim(),
    };
  })
);

const filteredRecords = computed(() => {
  if (!searchTerm.value) return records.value;

  return picoSearch(records.value, searchTerm.value, [
    { name: 'shortCode', weight: 1 },
    'plainText',
  ]);
});

const items = computed(() =>
  filteredRecords.value.map(record => ({
    id: record.id,
    content: record.content,
    resolved: record.resolved,
    label: `/${record.shortCode}`,
    title: highlightMatches(`/${record.shortCode}`),
    subtitle: highlightMatches(buildSnippet(record.plainText)),
  }))
);

const fetchCannedResponses = () => {
  store.dispatch('getCannedResponse', {
    searchKey: props.searchKey,
    usable: true,
  });
};

const onSelect = item => emit('replace', item.content);

watch(
  () => props.searchKey,
  value => {
    searchQuery.value = value;
    fetchCannedResponses();
  }
);

onMounted(fetchCannedResponses);
</script>

<template>
  <CaretAnchoredPicker
    v-model:search="searchQuery"
    :caret-position="caretPosition"
    :focus-search="focusSearch"
    touch-preview
    :items="items"
    :search-placeholder="t('COMBOBOX.SEARCH_PLACEHOLDER')"
    :is-loading="uiFlags.fetchingList"
    :empty-label="
      searchTerm
        ? t('COMBOBOX.EMPTY_SEARCH_RESULTS', { searchTerm })
        : t('COMBOBOX.EMPTY_STATE')
    "
    @select="onSelect"
    @close="emit('close')"
    @remove-trigger="emit('removeTrigger')"
  >
    <template #preview="{ item }">
      <ShortcutPreview :content="item?.resolved || ''" class="px-4 py-3" />
    </template>
  </CaretAnchoredPicker>
</template>
