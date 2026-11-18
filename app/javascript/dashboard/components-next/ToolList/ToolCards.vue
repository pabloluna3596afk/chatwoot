<script setup>
import {
  computed,
  nextTick,
  onBeforeUnmount,
  onMounted,
  onUpdated,
  ref,
} from 'vue';
import { useMessageFormatter } from 'shared/composables/useMessageFormatter';

const props = defineProps({
  items: { type: Array, default: () => [] },
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
  copiedLabel: { type: String, default: 'Copied' },
  creatorLabel: { type: String, default: 'Created' },
  reviewerLabel: { type: String, default: 'Approved' },
  createdBy: { type: Function, default: item => item.created_by },
  reviewedBy: { type: Function, default: item => item.reviewed_by },
  createdAt: { type: Function, default: item => item.created_at },
  reviewedAt: { type: Function, default: item => item.reviewed_at },
  canEdit: { type: Function, default: () => true },
  statusLabel: { type: Function, default: item => item.status },
  visibilityLabel: { type: Function, default: item => item.visibility },
  variableLabels: { type: Object, default: () => ({}) },
  getKey: { type: Function, default: item => item.id },
});

const emit = defineEmits(['action', 'edit']);
const { formatMessage } = useMessageFormatter();
const expanded = ref(new Set());
const copied = ref(new Set());
const timers = new Map();
const visibleActions = item =>
  props.actions.filter(action => !action.visible || action.visible(item));
const variableName = part => {
  const path = part.replace(/[{}]/g, '').trim();
  if (props.variableLabels[path]) return props.variableLabels[path];
  const customAttribute = path.match(
    /^(?:contact|conversation|company)\.custom_attribute(?:\[['"]?(.+?)['"]?\]|\.(.+))?$/
  );
  if (customAttribute) {
    const key = customAttribute[1] || customAttribute[2];
    const label = props.variableLabels['contact.custom_attribute'];
    return key ? `${label}: ${key}` : label;
  }
  return props.variableLabels[path] || path.replace(/[._]/g, ' ');
};
// A card expands only when its clamped text is really cut: measure the rendered height.
const truncated = ref(new Set());
const textElements = new Map();
let resizeObserver = null;
const measure = () => {
  const next = new Set();
  textElements.forEach((element, key) => {
    // An expanded card is not clamped any more: keep what we knew before.
    if (expanded.value.has(key)) {
      if (truncated.value.has(key)) next.add(key);
      return;
    }
    if (element.scrollHeight - element.clientHeight > 1) next.add(key);
  });
  const unchanged =
    next.size === truncated.value.size &&
    [...next].every(key => truncated.value.has(key));
  if (!unchanged) truncated.value = next;
};
const setTextElement = (key, element) => {
  if (element) {
    textElements.set(key, element);
    resizeObserver?.observe(element);
  } else {
    textElements.delete(key);
  }
};
const isTruncated = item => truncated.value.has(props.getKey(item));
const toggleExpanded = id => {
  const next = new Set(expanded.value);
  if (next.has(id)) next.delete(id);
  else next.add(id);
  expanded.value = next;
};
const editItem = item => {
  if (props.canEdit(item)) emit('edit', item);
};
const runAction = (action, item, event) => {
  event.stopPropagation();
  event.currentTarget.closest('details')?.removeAttribute('open');
  emit('action', { action: action.key, item });
};
const copyContent = async item => {
  await navigator.clipboard.writeText(item[props.contentKey] || '');
  const id = props.getKey(item);
  copied.value = new Set([...copied.value, id]);
  clearTimeout(timers.get(id));
  timers.set(
    id,
    setTimeout(() => {
      copied.value = new Set([...copied.value].filter(key => key !== id));
    }, 1500)
  );
};
const isCopied = item => copied.value.has(props.getKey(item));
const traceLabel = (label, person, date) =>
  person
    ? `${label} ${person.available_name || person.email || ''} · ${date}`
    : '';
const statusIcon = item =>
  ({
    pending: 'i-lucide-clock text-n-amber-11',
    approved: 'i-lucide-circle-check text-n-teal-11',
    rejected: 'i-lucide-circle-x text-n-ruby-9',
  })[item[props.statusKey]] || 'i-lucide-circle-help text-n-slate-10';
const visibilityIcon = item =>
  item[props.visibilityKey] === 'global'
    ? 'i-lucide-building-2 text-n-brand'
    : 'i-lucide-user-round text-n-slate-11';
const visibleVariableText = part => variableName(part);
// Paragraph spacing only in the expanded overlay: in the collapsed card every paragraph
// is one clamped line, so the measured height matches the line count.
const overlayClasses = '[&_p+p]:mt-2';
const escapeHtml = value =>
  String(value)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
// Canned responses are markdown: render bold, line breaks, lists and links like the
// chat does, keeping each {{ variable }} as a chip. The result is sanitized by the
// v-dompurify-html directive where it is used.
const renderContent = content => {
  const variables = [];
  const text = String(content || '').replace(/\{\{[^{}]+\}\}/g, match => {
    variables.push(match);
    return `CANNEDVAR${variables.length - 1}X`;
  });
  return formatMessage(text, false, false, false).replace(
    /CANNEDVAR(\d+)X/g,
    (_, index) =>
      `<span class="inline break-words rounded bg-n-brand/10 px-1 text-n-blue-12" title="${escapeHtml(variables[index])}">${escapeHtml(visibleVariableText(variables[index]))}</span>`
  );
};
const contentClasses =
  '[&_p]:m-0 [&_ul]:m-0 [&_ul]:list-disc [&_ul]:ps-5 [&_ol]:m-0 [&_ol]:list-decimal [&_ol]:ps-5 [&_a]:underline [&_a]:text-n-brand [&_strong]:font-semibold';
const cardTabIndex = item => (props.canEdit(item) ? 0 : -1);
const onCardKeydown = (event, item) => {
  if (event.key === 'Enter' || event.key === ' ') {
    event.preventDefault();
    editItem(item);
  }
};
const closeMenuOnEscape = event => {
  if (event.key !== 'Escape') return;
  const details = event.currentTarget;
  if (!details.open) return;
  details.open = false;
  details.querySelector('summary')?.focus();
};
const cards = computed(() => props.items);
// The action menu is a native <details>: close it when the user clicks anywhere else.
const closeMenusOnOutsideClick = event => {
  document.querySelectorAll('details[data-card-menu][open]').forEach(menu => {
    if (!menu.contains(event.target)) menu.removeAttribute('open');
  });
};
onMounted(() => {
  document.addEventListener('click', closeMenusOnOutsideClick);
  if (typeof ResizeObserver !== 'undefined') {
    resizeObserver = new ResizeObserver(measure);
    textElements.forEach(element => resizeObserver.observe(element));
  }
  nextTick(measure);
  document.fonts?.ready?.then(measure);
});
onUpdated(measure);
onBeforeUnmount(() => {
  document.removeEventListener('click', closeMenusOnOutsideClick);
  resizeObserver?.disconnect();
});
</script>

<template>
  <section class="w-full min-w-0">
    <div v-if="!cards.length" class="p-8 text-center text-n-slate-11">
      {{ emptyMessage }}
    </div>
    <div v-else class="columns-1 gap-3 sm:columns-2 xl:columns-3">
      <article
        v-for="item in cards"
        :key="getKey(item)"
        class="group relative mb-3 inline-block w-full break-inside-avoid rounded-xl border border-n-weak bg-n-surface-1 shadow-sm hover:z-40 hover:shadow-lg focus-within:z-40 has-[details[open]]:z-50"
      >
        <div class="flex items-start gap-2 p-4 pb-2">
          <button
            type="button"
            class="min-w-0 flex-1 text-start focus-visible:rounded focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :aria-label="`${item[titleKey]}, ${editLabel}`"
            :tabindex="cardTabIndex(item)"
            @click="editItem(item)"
            @keydown="onCardKeydown($event, item)"
          >
            <span class="block truncate font-semibold text-n-slate-12">{{
              item[titleKey]
            }}</span>
          </button>
          <button
            type="button"
            class="flex size-8 shrink-0 items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2"
            :aria-label="copyLabel"
            :title="copyLabel"
            @click.stop="copyContent(item)"
          >
            <span
              :class="
                isCopied(item)
                  ? 'i-lucide-check text-n-teal-11'
                  : 'i-lucide-copy'
              "
              class="size-4"
            />
          </button>
          <span class="sr-only" aria-live="polite">{{
            isCopied(item) ? copiedLabel : ''
          }}</span>
          <details
            v-if="visibleActions(item).length"
            data-card-menu
            class="relative z-30 shrink-0"
            @keydown="closeMenuOnEscape"
          >
            <summary
              class="flex size-8 cursor-pointer list-none items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2 focus-visible:outline focus-visible:outline-2"
              :aria-label="moreOptionsLabel"
            >
              <span class="i-lucide-ellipsis size-5" />
            </summary>
            <div
              class="absolute end-0 top-full z-40 max-h-[min(50vh,20rem)] w-56 overflow-y-auto rounded-lg border border-n-weak bg-n-surface-1 p-1 shadow-lg"
              role="menu"
            >
              <button
                v-for="action in visibleActions(item)"
                :key="action.key"
                type="button"
                role="menuitem"
                class="flex w-full items-center gap-2 rounded-md px-3 py-2 text-start text-sm hover:bg-n-alpha-2"
                :class="{
                  'text-n-teal-11': action.variant === 'success',
                  'text-n-ruby-9': action.variant === 'danger',
                }"
                @click="runAction(action, item, $event)"
              >
                <span
                  :class="action.icon"
                  class="size-4 shrink-0"
                  aria-hidden="true"
                />
                {{ action.label }}
              </button>
            </div>
          </details>
        </div>
        <div class="group/content relative px-4 pb-3" data-card-content>
          <button
            type="button"
            class="block w-full text-start focus-visible:outline focus-visible:outline-2 focus-visible:outline-n-brand"
            :class="
              isTruncated(item)
                ? '[@media(hover:hover)]:group-hover/content:invisible [@media(hover:hover)]:focus:invisible'
                : ''
            "
            :aria-label="`${editLabel}: ${item[titleKey]}`"
            @click="editItem(item)"
          >
            <span
              :ref="element => setTextElement(getKey(item), element)"
              v-dompurify-html="renderContent(item[contentKey])"
              class="line-clamp-6 break-words text-sm leading-5 text-n-slate-11"
              :class="[
                contentClasses,
                expanded.has(getKey(item))
                  ? 'line-clamp-none overflow-visible'
                  : '',
              ]"
            />
          </button>
          <div
            v-if="isTruncated(item)"
            class="hidden [@media(hover:hover)]:group-hover/content:block [@media(hover:hover)]:group-focus-within/content:block"
          >
            <div
              class="absolute inset-x-0 top-0 z-20 max-h-[min(70vh,36rem)] overflow-y-auto rounded-xl border border-n-weak bg-n-surface-1 p-4 pt-2 shadow-xl"
            >
              <button
                type="button"
                class="block w-full text-start text-sm leading-5 text-n-slate-12"
                :aria-label="`${editLabel}: ${item[titleKey]}`"
                @click="editItem(item)"
              >
                <span
                  v-dompurify-html="renderContent(item[contentKey])"
                  class="block break-words"
                  :class="[contentClasses, overlayClasses]"
                />
              </button>
              <div
                class="mt-3 flex flex-wrap gap-x-3 gap-y-1 border-t border-n-weak pt-2 text-xs text-n-slate-10"
              >
                <span v-if="createdBy(item)">{{
                  traceLabel(creatorLabel, createdBy(item), createdAt(item))
                }}</span>
                <span v-if="reviewedBy(item)">{{
                  traceLabel(reviewerLabel, reviewedBy(item), reviewedAt(item))
                }}</span>
              </div>
            </div>
          </div>
          <button
            v-if="isTruncated(item)"
            type="button"
            class="mt-1 text-xs font-medium text-n-brand [@media(hover:hover)]:hidden"
            :aria-expanded="expanded.has(getKey(item))"
            @click.stop="toggleExpanded(getKey(item))"
          >
            {{ expanded.has(getKey(item)) ? showLessLabel : showMoreLabel }}
          </button>
        </div>
        <div class="flex flex-wrap items-center gap-2 px-4 pb-3">
          <span
            v-if="item[categoryKey]"
            class="max-w-full truncate rounded-md bg-n-alpha-2 px-2 py-1 text-xs text-n-slate-11"
            >{{ item[categoryKey] }}</span
          >
          <span
            v-if="item[statusKey]"
            class="inline-flex"
            role="img"
            :title="statusLabel(item)"
            :aria-label="statusLabel(item)"
          >
            <span :class="statusIcon(item)" class="size-4" aria-hidden="true" />
          </span>
          <span
            v-if="item[visibilityKey]"
            class="inline-flex"
            role="img"
            :title="visibilityLabel(item)"
            :aria-label="visibilityLabel(item)"
            ><span
              :class="visibilityIcon(item)"
              class="size-4"
              aria-hidden="true"
          /></span>
        </div>
        <footer
          v-if="createdBy(item) || reviewedBy(item)"
          class="flex flex-wrap gap-x-3 gap-y-1 border-t border-n-weak px-4 py-2 text-xs text-n-slate-11 motion-reduce:transition-none"
          :class="
            isTruncated(item)
              ? '[@media(hover:hover)]:sr-only'
              : '[@media(hover:hover)]:absolute [@media(hover:hover)]:inset-x-0 [@media(hover:hover)]:top-full [@media(hover:hover)]:-mt-px [@media(hover:hover)]:z-20 [@media(hover:hover)]:rounded-b-xl [@media(hover:hover)]:border [@media(hover:hover)]:border-n-weak [@media(hover:hover)]:bg-n-surface-1 [@media(hover:hover)]:shadow-lg [@media(hover:hover)]:pointer-events-none [@media(hover:hover)]:opacity-0 [@media(hover:hover)]:transition-opacity [@media(hover:hover)]:group-hover:opacity-100 [@media(hover:hover)]:group-focus-within:opacity-100'
          "
        >
          <span
            v-if="createdBy(item)"
            :title="traceLabel(creatorLabel, createdBy(item), createdAt(item))"
            >{{
              traceLabel(creatorLabel, createdBy(item), createdAt(item))
            }}</span
          >
          <span
            v-if="reviewedBy(item)"
            :title="
              traceLabel(reviewerLabel, reviewedBy(item), reviewedAt(item))
            "
            >{{
              traceLabel(reviewerLabel, reviewedBy(item), reviewedAt(item))
            }}</span
          >
        </footer>
      </article>
    </div>
  </section>
</template>
