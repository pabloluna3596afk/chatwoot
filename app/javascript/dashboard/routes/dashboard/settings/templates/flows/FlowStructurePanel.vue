<script setup>
import { computed, nextTick, ref, toRaw } from 'vue';
import { useI18n } from 'vue-i18n';
import Draggable from 'vuedraggable';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import { BLOCK_TYPES, PALETTE, TEXT_TYPES } from './flowDefinition';

const props = defineProps({
  screens: { type: Array, required: true },
  screenIndex: { type: Number, required: true },
  selected: { type: Number, default: null },
  blockKey: { type: Function, required: true },
});
const emit = defineEmits([
  'selectScreen',
  'addScreen',
  'renameScreen',
  'removeScreen',
  'reorderScreens',
  'selectBlock',
  'addBlock',
  'removeBlock',
  'reorderBlocks',
]);
const { t } = useI18n();
const screenList = ref(null);
const fieldList = ref(null);
const catalog = ref(null);
const addFieldButton = ref(null);
const removeDialog = ref(null);
const pendingRemoval = ref(null);
const pendingRemovalIndex = ref(null);
const announcement = ref('');
const blocks = computed(() => props.screens[props.screenIndex].blocks);
const DRAG_OPTIONS = {
  animation: 150,
  ghostClass: 'opacity-40',
  delay: 150,
  delayOnTouchOnly: true,
};
const SCREEN_DRAG_GROUP = {
  name: 'whatsapp-flow-screens',
  pull: false,
  put: false,
};
const FIELD_DRAG_GROUP = {
  name: 'whatsapp-flow-fields',
  pull: false,
  put: false,
};
const screenKeys = new WeakMap();
let screenKeyCount = 0;
const screenKey = item => {
  const raw = toRaw(item);
  if (!screenKeys.has(raw)) {
    screenKeyCount += 1;
    screenKeys.set(raw, screenKeyCount);
  }
  return screenKeys.get(raw);
};
const screenLabel = (screen, index) =>
  t('WHATSAPP_FLOWS.EDITOR.SCREEN_TAB', {
    n: index + 1,
    title: screen.title || t('WHATSAPP_FLOWS.EDITOR.SCREEN_UNTITLED'),
  });
const fieldLabel = block => {
  if (TEXT_TYPES.includes(block.type))
    return block.text?.trim() || t(`WHATSAPP_FLOWS.BLOCKS.${block.type}`);
  const type = ['email', 'phone', 'number'].includes(block.input)
    ? block.input
    : block.type;
  return block.label?.trim() || t(`WHATSAPP_FLOWS.BLOCKS.${type}`);
};
const fieldIcon = block =>
  BLOCK_TYPES.find(item => item.type === block.type).icon;
const paletteGroups = computed(() => [
  { group: 'text', items: PALETTE.find(group => group.group === 'text').items },
  {
    group: 'answer',
    items: PALETTE.filter(group =>
      ['answer', 'options'].includes(group.group)
    ).flatMap(group => group.items),
  },
  {
    group: 'file',
    items: PALETTE.flatMap(group => group.items).filter(item =>
      ['photo', 'document'].includes(item.type)
    ),
  },
]);
const screenActions = index => [
  {
    action: 'up',
    icon: 'i-lucide-arrow-up',
    label: t('WHATSAPP_FLOWS.EDITOR.MOVE_UP'),
    disabled: index === 0,
    testId: 'flow-screen-move-up',
  },
  {
    action: 'down',
    icon: 'i-lucide-arrow-down',
    label: t('WHATSAPP_FLOWS.EDITOR.MOVE_DOWN'),
    disabled: index === props.screens.length - 1,
    testId: 'flow-screen-move-down',
  },
  {
    action: 'rename',
    icon: 'i-lucide-pencil',
    label: t('WHATSAPP_FLOWS.EDITOR.RENAME_SCREEN'),
    testId: 'flow-screen-rename',
  },
  {
    action: 'delete',
    icon: 'i-lucide-trash-2',
    label: t('WHATSAPP_FLOWS.EDITOR.REMOVE_SCREEN'),
    disabled: props.screens.length === 1,
    testId: 'flow-screen-remove',
  },
];
const fieldActions = index => [
  {
    action: 'up',
    icon: 'i-lucide-arrow-up',
    label: t('WHATSAPP_FLOWS.EDITOR.MOVE_UP'),
    disabled: index === 0,
    testId: 'flow-field-move-up',
  },
  {
    action: 'down',
    icon: 'i-lucide-arrow-down',
    label: t('WHATSAPP_FLOWS.EDITOR.MOVE_DOWN'),
    disabled: index === blocks.value.length - 1,
    testId: 'flow-field-move-down',
  },
  {
    action: 'delete',
    icon: 'i-lucide-trash-2',
    label: t('WHATSAPP_FLOWS.EDITOR.REMOVE_BLOCK'),
    testId: 'flow-field-remove',
  },
];
const moveItem = (kind, index, step) => {
  const ordered = [...(kind === 'screen' ? props.screens : blocks.value)];
  const target = index + step;
  if (target < 0 || target >= ordered.length) return;
  const [moved] = ordered.splice(index, 1);
  ordered.splice(target, 0, moved);
  emit(kind === 'screen' ? 'reorderScreens' : 'reorderBlocks', ordered);
  announcement.value = t('WHATSAPP_FLOWS.EDITOR.ITEM_MOVED', {
    n: target + 1,
    total: ordered.length,
  });
  nextTick(() => {
    const list = kind === 'screen' ? screenList.value : fieldList.value;
    list?.$el
      ?.querySelectorAll(`[data-testid="flow-${kind}-select"]`)
      [target]?.focus();
  });
};
const onKeydown = (event, kind, index) => {
  if (
    !(event.altKey || event.ctrlKey) ||
    !['ArrowUp', 'ArrowDown'].includes(event.key)
  )
    return;
  event.preventDefault();
  moveItem(kind, index, event.key === 'ArrowUp' ? -1 : 1);
};
const onScreenAction = (item, index) => {
  if (item.action === 'rename') emit('renameScreen', index);
  else if (item.action === 'delete') emit('removeScreen', index);
  else moveItem('screen', index, item.action === 'up' ? -1 : 1);
};
const onFieldAction = (item, index) => {
  if (item.action !== 'delete') {
    moveItem('field', index, item.action === 'up' ? -1 : 1);
    return;
  }
  pendingRemoval.value = blocks.value[index];
  pendingRemovalIndex.value = index;
  removeDialog.value.open();
};
const confirmRemoval = () => {
  const index = blocks.value.indexOf(pendingRemoval.value);
  if (index >= 0) emit('removeBlock', index);
  removeDialog.value.close();
};
const restoreFieldFocus = () => {
  const index = Math.min(pendingRemovalIndex.value, blocks.value.length - 1);
  nextTick(() => {
    if (index >= 0)
      fieldList.value?.$el
        ?.querySelectorAll('[data-testid="flow-field-select"]')
        [index]?.focus();
    else addFieldButton.value?.$el?.focus();
  });
  pendingRemoval.value = null;
  pendingRemovalIndex.value = null;
};
const focusScreen = index =>
  nextTick(() => {
    screenList.value?.$el
      ?.querySelectorAll('[data-testid="flow-screen-select"]')
      [index]?.focus();
  });
defineExpose({ focusScreen });
const addBlock = item => {
  emit('addBlock', item);
  catalog.value.close();
};
</script>

<template>
  <section class="flex min-w-0 flex-col gap-5" data-testid="flow-structure">
    <p id="flow-structure-hint" class="sr-only">
      {{ $t('WHATSAPP_FLOWS.EDITOR.STRUCTURE_HINT') }}
    </p>
    <span class="sr-only" role="status" aria-live="polite">{{
      announcement
    }}</span>
    <div class="grid min-w-0 gap-2">
      <div class="flex items-center justify-between gap-2">
        <h2 class="m-0 text-heading-3 text-n-slate-12">
          {{ $t('WHATSAPP_FLOWS.EDITOR.SCREENS') }}
        </h2>
        <Button
          type="button"
          intent="tertiary"
          sm
          icon="i-lucide-plus"
          :aria-label="$t('WHATSAPP_FLOWS.EDITOR.ADD_SCREEN')"
          data-testid="flow-screen-add"
          @click="emit('addScreen')"
        />
      </div>
      <Draggable
        ref="screenList"
        :model-value="screens"
        :item-key="screenKey"
        :group="SCREEN_DRAG_GROUP"
        handle=".flow-screen-handle"
        v-bind="DRAG_OPTIONS"
        class="grid min-w-0 gap-1"
        role="list"
        :aria-label="$t('WHATSAPP_FLOWS.EDITOR.SCREENS')"
        aria-describedby="flow-structure-hint"
        data-testid="flow-screen-draggable"
        @update:model-value="emit('reorderScreens', $event)"
      >
        <template #item="{ element: screen, index }">
          <div
            class="flex min-w-0 items-center gap-1 rounded-lg px-1 py-0.5"
            :class="
              index === screenIndex
                ? 'bg-n-alpha-2 font-medium'
                : 'hover:bg-n-alpha-2'
            "
            role="listitem"
            @keydown="onKeydown($event, 'screen', index)"
          >
            <Button
              type="button"
              intent="tertiary"
              sm
              icon="i-lucide-grip-vertical"
              class="flow-screen-handle cursor-grab touch-none"
              :aria-label="$t('WHATSAPP_FLOWS.EDITOR.DRAG_SCREEN')"
              data-testid="flow-screen-handle"
            />
            <button
              type="button"
              class="min-w-0 flex-1 truncate py-2 text-start text-sm text-n-slate-12"
              :aria-pressed="index === screenIndex"
              aria-keyshortcuts="Alt+ArrowUp Alt+ArrowDown"
              data-testid="flow-screen-select"
              @click="emit('selectScreen', index)"
            >
              {{ screenLabel(screen, index) }}
            </button>
            <MenuPopover
              :menu-items="screenActions(index)"
              :restore-focus-on-select="false"
              :label="
                $t('WHATSAPP_FLOWS.EDITOR.ACTIONS_FOR', {
                  name: screenLabel(screen, index),
                })
              "
              @action="onScreenAction($event, index)"
            >
              <template #trigger="{ toggle }">
                <Button
                  type="button"
                  intent="tertiary"
                  sm
                  icon="i-lucide-ellipsis"
                  :aria-label="
                    $t('WHATSAPP_FLOWS.EDITOR.ACTIONS_FOR', {
                      name: screenLabel(screen, index),
                    })
                  "
                  data-testid="flow-screen-actions"
                  @click="toggle"
                />
              </template>
            </MenuPopover>
          </div>
        </template>
      </Draggable>
    </div>

    <div class="grid min-w-0 gap-2 border-t border-n-weak pt-4">
      <h2 class="m-0 text-heading-3 text-n-slate-12">
        {{ $t('WHATSAPP_FLOWS.EDITOR.SCREEN_FIELDS') }}
      </h2>
      <Draggable
        :key="screenIndex"
        ref="fieldList"
        :model-value="blocks"
        :item-key="blockKey"
        :group="FIELD_DRAG_GROUP"
        handle=".flow-field-handle"
        v-bind="DRAG_OPTIONS"
        class="grid min-w-0 gap-1"
        role="list"
        :aria-label="$t('WHATSAPP_FLOWS.EDITOR.SCREEN_FIELDS')"
        aria-describedby="flow-structure-hint"
        data-testid="flow-field-draggable"
        @update:model-value="emit('reorderBlocks', $event)"
      >
        <template #item="{ element: block, index }">
          <div
            class="flex min-w-0 items-center gap-1 rounded-lg px-1 py-0.5"
            :class="
              selected === index
                ? 'bg-n-alpha-2 font-medium'
                : 'hover:bg-n-alpha-2'
            "
            role="listitem"
            @keydown="onKeydown($event, 'field', index)"
          >
            <Button
              type="button"
              intent="tertiary"
              sm
              icon="i-lucide-grip-vertical"
              class="flow-field-handle cursor-grab touch-none"
              :aria-label="$t('WHATSAPP_FLOWS.EDITOR.DRAG_BLOCK')"
              data-testid="flow-field-handle"
            />
            <button
              type="button"
              class="flex min-w-0 flex-1 items-center gap-2 py-2 text-start text-sm text-n-slate-12"
              :aria-pressed="selected === index"
              aria-keyshortcuts="Alt+ArrowUp Alt+ArrowDown"
              data-testid="flow-field-select"
              @click="emit('selectBlock', index)"
            >
              <span
                :class="fieldIcon(block)"
                class="size-4 shrink-0 text-n-slate-11"
                aria-hidden="true"
              />
              <span class="truncate">{{ fieldLabel(block) }}</span>
              <span
                v-if="block.visible_when"
                class="i-lucide-eye size-3.5 shrink-0 text-n-slate-11"
                role="img"
                :aria-label="$t('WHATSAPP_FLOWS.EDITOR.HAS_CONDITION')"
                :title="$t('WHATSAPP_FLOWS.EDITOR.HAS_CONDITION')"
              />
            </button>
            <MenuPopover
              :menu-items="fieldActions(index)"
              :restore-focus-on-select="false"
              :label="
                $t('WHATSAPP_FLOWS.EDITOR.ACTIONS_FOR', {
                  name: fieldLabel(block),
                })
              "
              @action="onFieldAction($event, index)"
            >
              <template #trigger="{ toggle }">
                <Button
                  type="button"
                  intent="tertiary"
                  sm
                  icon="i-lucide-ellipsis"
                  :aria-label="
                    $t('WHATSAPP_FLOWS.EDITOR.ACTIONS_FOR', {
                      name: fieldLabel(block),
                    })
                  "
                  data-testid="flow-field-actions"
                  @click="toggle"
                />
              </template>
            </MenuPopover>
          </div>
        </template>
      </Draggable>
      <p v-if="!blocks.length" class="m-0 text-sm text-n-slate-11">
        {{ $t('WHATSAPP_FLOWS.EDITOR.NO_FIELDS') }}
      </p>
      <Button
        ref="addFieldButton"
        type="button"
        intent="secondary"
        sm
        icon="i-lucide-plus"
        :label="$t('WHATSAPP_FLOWS.EDITOR.ADD_BLOCK')"
        class="w-full"
        data-testid="flow-field-add"
        @click="catalog.open()"
      />
    </div>

    <Dialog
      ref="catalog"
      body-scroll
      :title="$t('WHATSAPP_FLOWS.EDITOR.ADD_BLOCK')"
      :description="$t('WHATSAPP_FLOWS.EDITOR.CATALOG_HINT')"
      data-testid="flow-field-catalog"
      @close="addFieldButton?.$el?.focus()"
    >
      <div class="grid gap-4" data-testid="flow-palette">
        <section
          v-for="group in paletteGroups"
          :key="group.group"
          class="grid grid-cols-2 gap-1"
        >
          <h3 class="col-span-2 m-0 mb-1 text-heading-3 text-n-slate-12">
            {{ $t(`WHATSAPP_FLOWS.EDITOR.GROUPS.${group.group}`) }}
          </h3>
          <Button
            v-for="item in group.items"
            :key="item.id"
            type="button"
            intent="tertiary"
            sm
            :icon="item.icon"
            :label="$t(`WHATSAPP_FLOWS.BLOCKS.${item.id}`)"
            class="justify-start"
            :data-testid="`flow-add-${item.id}`"
            @click="addBlock(item)"
          />
        </section>
      </div>
      <template #footer>
        <div class="flex justify-end">
          <Button
            type="button"
            intent="secondary"
            :label="$t('WHATSAPP_FLOWS.META.CLOSE')"
            @click="catalog.close()"
          />
        </div>
      </template>
    </Dialog>
    <Dialog
      ref="removeDialog"
      type="alert"
      :title="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_BLOCK_TITLE')"
      :description="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_BLOCK_DESCRIPTION')"
      :confirm-button-label="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_BLOCK')"
      data-testid="flow-block-remove-dialog"
      @confirm="confirmRemoval"
      @close="restoreFieldFocus"
    />
  </section>
</template>
