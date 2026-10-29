<script setup>
import { computed, ref } from 'vue';
import Avatar from 'dashboard/components-next/avatar/Avatar.vue';

const props = defineProps({
  items: { type: Array, default: () => [] },
  variant: { type: String, default: 'keep' },
  actions: { type: Array, default: () => [] },
  titleKey: { type: String, default: 'name' },
  contentKey: { type: String, default: 'content' },
  categoryKey: { type: String, default: 'category' },
  statusKey: { type: String, default: 'status' },
  visibilityKey: { type: String, default: 'visibility' },
  emptyMessage: { type: String, default: '' },
  moreOptionsLabel: { type: String, default: 'More options' },
  showMoreLabel: { type: String, default: 'Show more' },
  showLessLabel: { type: String, default: 'Show less' },
  editLabel: { type: String, default: 'Edit' },
  copyLabel: { type: String, default: 'Copy' },
  closePreviewLabel: { type: String, default: 'Close preview' },
  creatorLabel: { type: String, default: 'Created' },
  reviewerLabel: { type: String, default: 'Approved' },
  createdBy: { type: Function, default: item => item.created_by },
  reviewedBy: { type: Function, default: item => item.reviewed_by },
  createdAt: { type: Function, default: item => item.created_at },
  reviewedAt: { type: Function, default: item => item.reviewed_at },
  canEdit: { type: Function, default: () => true },
  statusLabel: { type: Function, default: item => item.status },
  visibilityLabel: { type: Function, default: item => item.visibility },
  getKey: { type: Function, default: item => item.id },
});

const emit = defineEmits(['action', 'edit']);
const expanded = ref(new Set());
const selectedItem = ref(null);
const showMobilePreview = ref(false);
const previewItem = computed(() => selectedItem.value || props.items[0]);
const visibleActions = item =>
  props.actions.filter(action => !action.visible || action.visible(item));
const toggleExpanded = id => {
  const next = new Set(expanded.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  expanded.value = next;
};
const contentParts = content =>
  String(content || '')
    .split(/(\{\{[^{}]+\}\})/g)
    .filter(Boolean);
const needsExpansion = content =>
  String(content || '').length > 400 ||
  String(content || '').split('\n').length > 8;
const runAction = (action, item, event) => {
  event.stopPropagation();
  event.currentTarget.closest('details')?.removeAttribute('open');
  emit('action', { action: action.key, item });
};
const selectItem = item => {
  selectedItem.value = item;
  if (window.matchMedia('(max-width: 767px)').matches)
    showMobilePreview.value = true;
};
const editItem = item => {
  if (props.canEdit(item)) emit('edit', item);
};
const handleArrowFocus = event => {
  if (!['ArrowDown', 'ArrowUp'].includes(event.key)) return;
  const root = event.currentTarget.closest('[data-tool-cards]');
  const buttons = [...root.querySelectorAll('[data-card-focus]')];
  const currentIndex = buttons.indexOf(event.currentTarget);
  const direction = event.key === 'ArrowDown' ? 1 : -1;
  const next = buttons[currentIndex + direction];
  if (next) {
    event.preventDefault();
    next.focus();
  }
};
const copyContent = async item => {
  await navigator.clipboard.writeText(item[props.contentKey] || '');
};
const statusClass = item =>
  ({
    pending: 'bg-n-amber-3 text-n-amber-12',
    rejected: 'bg-n-ruby-3 text-n-ruby-11',
    approved: 'bg-n-teal-3 text-n-teal-12',
  })[item[props.statusKey]] || 'bg-n-alpha-2 text-n-slate-11';
const personName = person => person?.available_name || person?.email || '';
</script>

<template>
  <section class="w-full min-w-0" :data-variant="variant">
    <div v-if="!items.length" class="p-8 text-center text-n-slate-11">
      {{ emptyMessage }}
    </div>
    <div
      v-else-if="variant === 'panel'"
      class="grid min-w-0 gap-4 md:grid-cols-[minmax(16rem,0.8fr)_minmax(0,1.2fr)]"
    >
      <div class="grid content-start gap-2" data-tool-cards>
        <button
          v-for="item in items"
          :key="getKey(item)"
          type="button"
          class="min-w-0 rounded-xl border border-n-weak bg-n-surface-1 p-3 text-start hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
          :class="{ 'border-n-brand': getKey(previewItem) === getKey(item) }"
          data-card-focus
          @keydown="handleArrowFocus"
          @mouseenter="selectedItem = item"
          @focus="selectedItem = item"
          @click="selectItem(item)"
          @dblclick="editItem(item)"
        >
          <span class="block truncate font-medium text-n-slate-12">{{
            item[titleKey]
          }}</span>
          <span
            class="mt-1 line-clamp-2 whitespace-pre-wrap text-sm text-n-slate-11"
            >{{ item[contentKey] }}</span
          >
        </button>
      </div>
      <div
        v-if="previewItem"
        class="hidden min-w-0 rounded-xl border border-n-weak bg-n-surface-1 p-5 md:block"
      >
        <div class="mb-4 flex flex-wrap items-center gap-2">
          <h3 class="me-auto text-heading-3 text-n-slate-12">
            {{ previewItem[titleKey] }}
          </h3>
          <span
            v-if="previewItem[categoryKey]"
            class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
            >{{ previewItem[categoryKey] }}</span
          >
          <span
            v-if="previewItem[statusKey]"
            class="rounded-md px-2 py-1 text-xs"
            :class="statusClass(previewItem)"
            >{{ statusLabel(previewItem) }}</span
          >
          <span
            v-if="previewItem[visibilityKey]"
            class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
            >{{ visibilityLabel(previewItem) }}</span
          >
          <details v-if="visibleActions(previewItem).length" class="relative">
            <summary
              class="flex size-8 cursor-pointer list-none items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2"
              :aria-label="moreOptionsLabel"
            >
              <span class="i-lucide-ellipsis size-5" />
            </summary>
            <div
              class="absolute end-0 top-full z-20 w-48 rounded-lg border border-n-weak bg-n-surface-1 p-1 shadow-lg"
              role="menu"
            >
              <button
                v-for="action in visibleActions(previewItem)"
                :key="action.key"
                type="button"
                role="menuitem"
                class="flex w-full rounded-md px-3 py-2 text-start text-sm hover:bg-n-alpha-2"
                :class="{
                  'text-n-teal-11': action.variant === 'success',
                  'text-n-ruby-9': action.variant === 'danger',
                }"
                @click="runAction(action, previewItem, $event)"
              >
                {{ action.label }}
              </button>
            </div>
          </details>
        </div>
        <div
          class="max-w-2xl whitespace-pre-wrap rounded-2xl rounded-es-sm bg-n-alpha-2 p-4 text-sm leading-6 text-n-slate-12"
        >
          <template
            v-for="(part, index) in contentParts(previewItem[contentKey])"
            :key="index"
          >
            <span
              v-if="part.startsWith('{{')"
              class="rounded bg-n-brand/10 px-1 text-n-brand"
              >{{ part }}</span
            ><span v-else>{{ part }}</span>
          </template>
        </div>
        <div class="mt-4 flex justify-end">
          <button
            v-if="canEdit(previewItem)"
            type="button"
            class="rounded-lg bg-n-brand px-3 py-2 text-sm text-white focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2"
            @click="editItem(previewItem)"
          >
            {{ $t('CANNED_MGMT.EDIT.BUTTON_TEXT') }}
          </button>
        </div>
      </div>
      <div
        v-if="showMobilePreview && previewItem"
        class="fixed inset-x-0 bottom-0 z-50 max-h-[85vh] overflow-y-auto rounded-t-2xl border border-n-weak bg-n-surface-1 p-5 shadow-xl md:hidden"
        role="dialog"
        aria-modal="true"
        :aria-label="previewItem[titleKey]"
      >
        <div class="mb-4 flex items-center">
          <h3 class="me-auto text-heading-3 text-n-slate-12">
            {{ previewItem[titleKey] }}
          </h3>
          <details v-if="visibleActions(previewItem).length" class="relative">
            <summary
              class="flex size-8 cursor-pointer list-none items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2"
              :aria-label="moreOptionsLabel"
            >
              <span class="i-lucide-ellipsis size-5" />
            </summary>
            <div
              class="absolute end-0 top-full z-20 w-48 rounded-lg border border-n-weak bg-n-surface-1 p-1 shadow-lg"
              role="menu"
            >
              <button
                v-for="action in visibleActions(previewItem)"
                :key="action.key"
                type="button"
                role="menuitem"
                class="flex w-full rounded-md px-3 py-2 text-start text-sm hover:bg-n-alpha-2"
                :class="{
                  'text-n-teal-11': action.variant === 'success',
                  'text-n-ruby-9': action.variant === 'danger',
                }"
                @click="runAction(action, previewItem, $event)"
              >
                {{ action.label }}
              </button>
            </div>
          </details>
          <button
            type="button"
            class="rounded-md p-2 text-n-slate-11 focus-visible:outline focus-visible:outline-2"
            :aria-label="closePreviewLabel"
            @click="showMobilePreview = false"
          >
            <span class="i-lucide-x size-5" />
          </button>
        </div>
        <div class="mb-3 flex flex-wrap gap-2">
          <span
            v-if="previewItem[categoryKey]"
            class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
            >{{ previewItem[categoryKey] }}</span
          >
          <span
            v-if="previewItem[statusKey]"
            class="rounded-md px-2 py-1 text-xs"
            :class="statusClass(previewItem)"
            >{{ statusLabel(previewItem) }}</span
          >
          <span
            v-if="previewItem[visibilityKey]"
            class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
            >{{ visibilityLabel(previewItem) }}</span
          >
        </div>
        <div
          class="whitespace-pre-wrap rounded-2xl bg-n-alpha-2 p-4 text-sm leading-6 text-n-slate-12"
        >
          <template
            v-for="(part, index) in contentParts(previewItem[contentKey])"
            :key="index"
          >
            <span
              v-if="part.startsWith('{{')"
              class="rounded bg-n-brand/10 px-1 text-n-brand"
              >{{ part }}</span
            ><span v-else>{{ part }}</span>
          </template>
        </div>
        <button
          v-if="canEdit(previewItem)"
          type="button"
          class="mt-4 w-full rounded-lg bg-n-brand px-3 py-2 text-sm text-white"
          @click="editItem(previewItem)"
        >
          {{ $t('CANNED_MGMT.EDIT.BUTTON_TEXT') }}
        </button>
      </div>
    </div>
    <div
      v-else
      data-tool-cards
      :class="
        variant === 'keep'
          ? 'columns-1 gap-3 sm:columns-2 xl:columns-3'
          : 'grid grid-cols-1 gap-3 sm:grid-cols-2 xl:grid-cols-3'
      "
    >
      <article
        v-for="(item, index) in items"
        :key="getKey(item)"
        class="group relative min-w-0 rounded-xl border border-n-weak bg-n-surface-1 shadow-sm hover:shadow-md"
        :class="
          variant === 'keep'
            ? 'mb-3 inline-block w-full break-inside-avoid'
            : ''
        "
      >
        <div class="flex items-start gap-2 p-4 pb-2">
          <button
            type="button"
            class="min-w-0 flex-1 text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-label="`${item[titleKey]}, ${editLabel}`"
            data-card-focus
            @click="editItem(item)"
            @keydown="handleArrowFocus"
          >
            <span class="block truncate font-semibold text-n-slate-12">{{
              item[titleKey]
            }}</span>
          </button>
          <details
            v-if="visibleActions(item).length"
            class="relative z-10 shrink-0"
          >
            <summary
              class="flex size-8 cursor-pointer list-none items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2"
              :aria-label="moreOptionsLabel"
            >
              <span class="i-lucide-ellipsis size-5" />
            </summary>
            <div
              class="absolute end-0 top-full z-20 max-h-[min(50vh,20rem)] w-48 overflow-y-auto rounded-lg border border-n-weak bg-n-surface-1 p-1 shadow-lg"
              :class="
                index >= Math.ceil(items.length / 2)
                  ? 'bottom-full mb-1 top-auto'
                  : ''
              "
              role="menu"
            >
              <button
                v-for="action in visibleActions(item)"
                :key="action.key"
                type="button"
                role="menuitem"
                class="flex w-full rounded-md px-3 py-2 text-start text-sm hover:bg-n-alpha-2"
                :class="{
                  'text-n-teal-11': action.variant === 'success',
                  'text-n-ruby-9': action.variant === 'danger',
                }"
                @click="runAction(action, item, $event)"
              >
                {{ action.label }}
              </button>
            </div>
          </details>
        </div>
        <div v-if="variant === 'accordion'" class="px-4 pb-3">
          <div class="flex items-start gap-2">
            <button
              type="button"
              class="min-w-0 flex-1 text-start focus-visible:outline focus-visible:outline-2"
              @click="editItem(item)"
            >
              <span
                class="line-clamp-3 whitespace-pre-wrap text-sm leading-5 text-n-slate-11"
                ><template
                  v-for="(part, partIndex) in contentParts(item[contentKey])"
                  :key="partIndex"
                  ><span
                    v-if="part.startsWith('{{')"
                    class="rounded bg-n-brand/10 px-1 text-n-brand"
                    >{{ part }}</span
                  ><span v-else>{{ part }}</span></template
                ></span
              >
            </button>
            <button
              type="button"
              class="flex size-8 shrink-0 items-center justify-center rounded-md text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2"
              :aria-label="
                expanded.has(getKey(item)) ? showLessLabel : showMoreLabel
              "
              :aria-expanded="expanded.has(getKey(item))"
              @click="toggleExpanded(getKey(item))"
            >
              <span
                class="i-lucide-chevron-down size-4 transition-transform"
                :class="{ 'rotate-180': expanded.has(getKey(item)) }"
              />
            </button>
          </div>
          <div
            v-if="expanded.has(getKey(item))"
            class="mt-2 whitespace-pre-wrap text-sm leading-6 text-n-slate-12"
          >
            <template
              v-for="(part, partIndex) in contentParts(item[contentKey])"
              :key="partIndex"
            >
              <span
                v-if="part.startsWith('{{')"
                class="rounded bg-n-brand/10 px-1 text-n-brand"
                >{{ part }}</span
              ><span v-else>{{ part }}</span>
            </template>
          </div>
        </div>
        <div v-else class="px-4 pb-3">
          <button
            type="button"
            class="block w-full text-start focus-visible:outline focus-visible:outline-2"
            @click="editItem(item)"
          >
            <span
              class="block whitespace-pre-wrap text-sm leading-5 text-n-slate-11"
              :class="expanded.has(getKey(item)) ? '' : 'line-clamp-8'"
            >
              <template
                v-for="(part, partIndex) in contentParts(item[contentKey])"
                :key="partIndex"
                ><span
                  v-if="part.startsWith('{{')"
                  class="rounded bg-n-brand/10 px-1 text-n-brand"
                  >{{ part }}</span
                ><span v-else>{{ part }}</span></template
              ></span
            >
          </button>
          <button
            v-if="needsExpansion(item[contentKey])"
            type="button"
            class="mt-1 text-xs font-medium text-n-brand"
            @click.stop="toggleExpanded(getKey(item))"
          >
            {{ expanded.has(getKey(item)) ? showLessLabel : showMoreLabel }}
          </button>
        </div>
        <div class="flex flex-wrap items-center gap-2 px-4 pb-3">
          <span
            v-if="item[categoryKey]"
            class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
            >{{ item[categoryKey] }}</span
          >
          <span
            v-if="item[statusKey]"
            class="rounded-md px-2 py-1 text-xs"
            :class="statusClass(item)"
            >{{ statusLabel(item) }}</span
          >
          <span
            v-if="item[visibilityKey]"
            class="rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
            >{{ visibilityLabel(item) }}</span
          >
          <button
            type="button"
            class="ms-auto rounded-md p-1.5 text-n-slate-10 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2"
            :aria-label="`${copyLabel} ${item[titleKey]}`"
            @click.stop="copyContent(item)"
          >
            <span class="i-lucide-copy size-4" />
          </button>
        </div>
        <footer
          class="flex flex-wrap gap-x-3 gap-y-1 border-t border-n-weak px-4 py-2 text-xs text-n-slate-10 [@media(hover:hover)]:opacity-0 [@media(hover:hover)]:transition-opacity [@media(hover:hover)]:group-hover:opacity-100 [@media(hover:hover)]:focus-within:opacity-100"
        >
          <span v-if="createdBy(item)">
            <span class="inline-flex items-center gap-1">
              <Avatar
                :name="personName(createdBy(item))"
                :src="createdBy(item).avatar_url"
                :size="16"
                rounded-full
              />
              <span>{{
                `${creatorLabel} ${personName(createdBy(item))} · ${createdAt(item)}`
              }}</span>
            </span>
          </span>
          <span v-if="reviewedBy(item)">
            <span class="inline-flex items-center gap-1">
              <Avatar
                :name="personName(reviewedBy(item))"
                :src="reviewedBy(item).avatar_url"
                :size="16"
                rounded-full
              />
              <span>{{
                `${reviewerLabel} ${personName(reviewedBy(item))} · ${reviewedAt(item)}`
              }}</span>
            </span>
          </span>
        </footer>
      </article>
    </div>
  </section>
</template>
