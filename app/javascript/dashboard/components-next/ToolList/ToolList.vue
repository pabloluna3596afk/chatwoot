<script setup>
import { computed } from 'vue';

const props = defineProps({
  items: { type: Array, default: () => [] },
  columns: { type: Array, default: () => [] },
  loading: { type: Boolean, default: false },
  error: { type: String, default: '' },
  emptyMessage: { type: String, default: '' },
  loadingLabel: { type: String, default: 'Loading' },
  actionsLabel: { type: String, default: 'Actions' },
  moreOptionsLabel: { type: String, default: 'More options' },
  selectLabel: { type: String, default: 'Select' },
  selectable: { type: Boolean, default: false },
  selectedIds: { type: Array, default: () => [] },
  actions: { type: Array, default: () => [] },
  getKey: { type: Function, default: item => item.id },
});
const emit = defineEmits(['select', 'action']);
const hasLead = computed(() => Boolean(props.items.length));
const actionLabel = action => action.label;
const visibleActions = item =>
  props.actions.filter(action => !action.visible || action.visible(item));
const menuPlacement = index =>
  index >= Math.ceil(props.items.length / 2)
    ? 'bottom-full mb-1'
    : 'top-full mt-1';
const run = (action, item, event) => {
  if (action.disabled?.(item)) return;
  event.currentTarget.closest('details')?.removeAttribute('open');
  emit('action', { action: action.key, item });
};
</script>

<template>
  <section class="w-full min-w-0 overflow-hidden" :aria-busy="loading">
    <div v-if="loading" class="space-y-3 p-4" role="status" aria-live="polite">
      <span class="sr-only">{{ loadingLabel }}</span>
      <div
        v-for="n in 3"
        :key="n"
        class="h-16 animate-pulse rounded-lg bg-n-alpha-2"
      />
    </div>
    <div v-else-if="error" class="p-6 text-center text-n-ruby-9" role="alert">
      {{ error }}
    </div>
    <div v-else-if="!items.length" class="p-8 text-center text-n-slate-11">
      {{ emptyMessage }}
    </div>
    <template v-else>
      <div class="grid gap-3 lg:hidden">
        <article
          v-for="(item, index) in items"
          :key="getKey(item)"
          class="min-w-0 rounded-xl border border-n-weak bg-n-surface-1 p-4 shadow-sm"
        >
          <div class="flex min-w-0 items-start gap-3">
            <input
              v-if="selectable"
              type="checkbox"
              :checked="selectedIds.includes(getKey(item))"
              :aria-label="`${selectLabel} ${item.name || getKey(item)}`"
              class="mt-1 size-4 accent-n-brand"
              @change="
                emit('select', { item, selected: $event.target.checked })
              "
            />
            <div class="min-w-0 flex-1">
              <slot v-if="$slots.lead" name="lead" :item="item" />
              <slot v-else name="title" :item="item">
                <h3 class="truncate font-medium text-n-slate-12">
                  {{ item.name }}
                </h3>
              </slot>
            </div>
            <details v-if="actions.length" class="relative shrink-0">
              <summary
                class="flex size-9 cursor-pointer list-none items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
                :aria-label="moreOptionsLabel"
              >
                <span class="i-lucide-ellipsis size-5" />
              </summary>
              <div
                class="absolute end-0 z-20 max-h-[min(50vh,20rem)] w-48 overflow-y-auto rounded-lg border border-n-weak bg-n-surface-1 p-1 shadow-lg"
                :class="menuPlacement(index)"
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
                  :disabled="action.disabled?.(item)"
                  @click="run(action, item, $event)"
                >
                  {{ actionLabel(action) }}
                </button>
              </div>
            </details>
          </div>
          <div class="mt-3 grid gap-2">
            <div
              v-for="column in columns.slice($slots.lead ? 1 : 0)"
              :key="column.key"
              class="flex min-w-0 justify-between gap-3 text-sm"
            >
              <span class="shrink-0 text-n-slate-10">{{ column.label }}</span>
              <span class="min-w-0 truncate text-end text-n-slate-12">
                <slot :name="`cell-${column.key}`" :item="item">
                  {{ item[column.key] }}
                </slot>
              </span>
            </div>
            <slot name="trace" :item="item" />
          </div>
          <slot name="row-actions" :item="item" />
        </article>
      </div>
      <div class="hidden w-full overflow-x-auto lg:block">
        <table
          class="w-full table-fixed border-separate border-spacing-0 text-sm"
        >
          <thead>
            <tr class="text-start text-n-slate-10">
              <th v-if="selectable" class="w-10 border-b border-n-weak p-3" />
              <th
                v-if="hasLead"
                class="w-1/3 border-b border-n-weak p-3 text-start"
              >
                {{ columns[0]?.label || '' }}
              </th>
              <th
                v-for="column in columns.slice(hasLead ? 1 : 0)"
                :key="column.key"
                class="border-b border-n-weak p-3 text-start"
              >
                {{ column.label }}
              </th>
              <th v-if="actions.length" class="w-12 border-b border-n-weak p-3">
                <span class="sr-only">{{ actionsLabel }}</span>
              </th>
            </tr>
          </thead>
          <tbody>
            <tr
              v-for="(item, index) in items"
              :key="getKey(item)"
              class="hover:bg-n-alpha-1"
            >
              <td v-if="selectable" class="border-b border-n-weak p-3">
                <input
                  type="checkbox"
                  :checked="selectedIds.includes(getKey(item))"
                  :aria-label="`${selectLabel} ${item.name || getKey(item)}`"
                  class="size-4 accent-n-brand"
                  @change="
                    emit('select', { item, selected: $event.target.checked })
                  "
                />
              </td>
              <td v-if="hasLead" class="border-b border-n-weak p-3">
                <slot v-if="$slots.lead" name="lead" :item="item" />
                <slot v-else name="title" :item="item">
                  <span class="font-medium text-n-slate-12">{{
                    item.name
                  }}</span>
                </slot>
                <slot name="trace" :item="item" />
              </td>
              <td
                v-for="column in columns.slice(hasLead ? 1 : 0)"
                :key="column.key"
                class="border-b border-n-weak p-3"
              >
                <slot :name="`cell-${column.key}`" :item="item">
                  {{ item[column.key] }}
                </slot>
              </td>
              <td v-if="actions.length" class="border-b border-n-weak p-2">
                <details class="relative">
                  <summary
                    class="flex size-9 cursor-pointer list-none items-center justify-center rounded-lg text-n-slate-11 hover:bg-n-alpha-2"
                    :aria-label="moreOptionsLabel"
                  >
                    <span class="i-lucide-ellipsis size-5" />
                  </summary>
                  <div
                    class="absolute end-0 z-20 max-h-[min(50vh,20rem)] w-48 overflow-y-auto rounded-lg border border-n-weak bg-n-surface-1 p-1 shadow-lg"
                    :class="menuPlacement(index)"
                    role="menu"
                  >
                    <button
                      v-for="action in visibleActions(item)"
                      :key="action.key"
                      type="button"
                      role="menuitem"
                      class="flex w-full items-center rounded-md px-3 py-2 text-start hover:bg-n-alpha-2"
                      :class="{
                        'text-n-teal-11': action.variant === 'success',
                        'text-n-ruby-9': action.variant === 'danger',
                      }"
                      :disabled="action.disabled?.(item)"
                      @click="run(action, item, $event)"
                    >
                      {{ actionLabel(action) }}
                    </button>
                  </div>
                </details>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </template>
  </section>
</template>
