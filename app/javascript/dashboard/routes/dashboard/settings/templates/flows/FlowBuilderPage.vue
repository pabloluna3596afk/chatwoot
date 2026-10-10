<script setup>
// The flow builder as a full page: the screens as tabs, the blocks to add on the left, the phone in the middle (blocks
// are edited by clicking them there) and the settings of the selected screen and block on the right. The mistakes Meta
// would refuse are shown while typing and the draft is saved on demand. A new flow is built in this same page: its
// name stays editable in properties; categories are in the header. The creation dialog chooses the starting content.
import {
  computed,
  nextTick,
  onBeforeUnmount,
  reactive,
  ref,
  toRaw,
  watch,
} from 'vue';
import Draggable from 'vuedraggable';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import FlowBlockEditor from './FlowBlockEditor.vue';
import FlowPhoneCanvas from './FlowPhoneCanvas.vue';
import FlowPhoneSimulator from './FlowPhoneSimulator.vue';
import FlowPublicationBadges from './FlowPublicationBadges.vue';
import FlowPublishDialog from './FlowPublishDialog.vue';
import FlowTestDialog from './FlowTestDialog.vue';
import { useFlowPublications } from './useFlowPublications';
import {
  CATEGORIES,
  LIMITS,
  PALETTE,
  groupErrors,
  newBlock,
  newScreen,
} from './flowDefinition';

const props = defineProps({
  // { id (null while it is new), name, categories, definition }; a new one comes with an empty screen
  flow: { type: Object, required: true },
  // The API the page talks to; only tests and the story give another one.
  api: { type: Object, default: () => WhatsappFlowsAPI },
});

const emit = defineEmits(['back', 'saved']);

const { t, te } = useI18n();
const store = useStore();
const attributes = computed(() => store.getters['attributes/getAttributes']);
store.dispatch('attributes/get');

const VALIDATE_DELAY = 500;
// A short press before a drag starts on a touch screen, so scrolling the page with a finger still works.
const DRAG_OPTIONS = {
  animation: 150,
  ghostClass: 'opacity-40',
  filter: '.flow-tab-remove',
  delay: 150,
  delayOnTouchOnly: true,
};

const name = ref(props.flow.name || '');
const categories = ref([...(props.flow.categories || [])]);
const definition = reactive(JSON.parse(JSON.stringify(props.flow.definition)));
const flowId = ref(props.flow.id || null);
const savedUnpublishedChanges = ref(props.flow.unpublished_changes || false);
const isSaving = ref(false);
const triedToSave = ref(false);
const errors = ref([]);
const flowJson = ref(null);
const jsonDialog = ref(null);
const tabsRef = ref(null);
const jsonCopied = ref(false);
const announcement = ref('');
const currentScreen = ref(0);
const selected = ref(null);
const isTrying = ref(false);
let timer = null;
const { run: runValidation } = useAbortableRequest();
const touched = ref(new Set());
const touch = path => touched.value.add(path);
let copiedTimer = null;

// What Meta says about the saved flow, per WhatsApp Cloud WABA (nothing shows for an account without one).
const {
  rows: metaRows,
  unpublishedChanges: metaUnpublishedChanges,
  wabas: metaWabas,
  hasCloud,
  isPublishing,
  load: loadMeta,
  publish: publishToMeta,
  retry: retryMeta,
  stop: stopMeta,
} = useFlowPublications(props.api, () => flowId.value);
const unpublishedChanges = computed(
  () => metaUnpublishedChanges.value ?? savedUnpublishedChanges.value
);
const statusLabel = computed(() => {
  if (isPublishing.value) return t('WHATSAPP_FLOWS.META.STATE.sending');
  const problem = metaRows.value.find(row =>
    ['error', 'blocked', 'throttled'].includes(row.state)
  );
  if (problem) return t(`WHATSAPP_FLOWS.META.STATE.${problem.state}`);
  if (unpublishedChanges.value)
    return t('WHATSAPP_FLOWS.META.UNPUBLISHED_CHANGES_BADGE');
  if (
    metaRows.value.length &&
    metaRows.value.every(row => row.state === 'published')
  )
    return t('WHATSAPP_FLOWS.META.STATE.published');
  return t('WHATSAPP_FLOWS.EDITOR.STATE_DRAFT');
});
const publishDialog = ref(null);
const testDialog = ref(null);

// What was last saved (or loaded); anything different is a change Meta would not see yet.
const snapshot = () =>
  JSON.stringify([name.value.trim(), categories.value, definition]);
const savedSnapshot = ref(snapshot());
const dirty = computed(() => snapshot() !== savedSnapshot.value);

const visibleErrors = computed(() =>
  triedToSave.value
    ? errors.value
    : errors.value.filter(error =>
        [...touched.value].some(
          path => error.path === path || error.path?.startsWith(`${path}.`)
        )
      )
);
const grouped = computed(() => groupErrors(visibleErrors.value));
// Publishing and testing send what is saved, so the flow has to be saved and free of mistakes first.
const metaBlocked = computed(
  () => !flowId.value || dirty.value || errors.value.length > 0
);
const metaHint = computed(() => {
  if (!flowId.value || dirty.value) return t('WHATSAPP_FLOWS.META.SAVE_FIRST');
  if (errors.value.length) return t('WHATSAPP_FLOWS.META.FIX_FIRST');
  return '';
});
const actionItems = computed(() => [
  // Probar = try the Flow right here in the phone; Enviar = send the saved Flow to a number (the old "Probar").
  {
    action: 'try',
    label: isTrying.value
      ? t('WHATSAPP_FLOWS.SIMULATOR.BACK_TO_EDIT')
      : t('WHATSAPP_FLOWS.EDITOR.ACTION_TRY'),
    icon: isTrying.value ? 'i-lucide-pencil' : 'i-lucide-play',
    testId: 'flow-preview-try',
  },
  ...(hasCloud.value
    ? [
        {
          action: 'test',
          label: t('WHATSAPP_FLOWS.EDITOR.ACTION_SEND'),
          icon: 'i-lucide-send',
          disabled: metaBlocked.value,
          title: metaHint.value,
          testId: 'flow-test-open',
        },
      ]
    : []),
  {
    action: 'json',
    label: t('WHATSAPP_FLOWS.EDITOR.SHOW_JSON'),
    icon: 'i-lucide-code',
    disabled: !flowJson.value,
    testId: 'flow-json-toggle',
  },
]);
const screen = computed(() => definition.screens[currentScreen.value]);
const block = computed(() =>
  selected.value === null ? null : screen.value?.blocks[selected.value]
);
const screenErrors = computed(() => grouped.value.screen[currentScreen.value]);

const check = async () => {
  try {
    await runValidation(async signal => {
      const { data } = await props.api.validate(
        JSON.parse(JSON.stringify(definition)),
        { signal }
      );
      if (signal.aborted) return;
      errors.value = data.errors || [];
      flowJson.value = data.flow_json;
    });
  } catch {
    errors.value = [];
  }
};

watch(
  definition,
  () => {
    clearTimeout(timer);
    timer = setTimeout(check, VALIDATE_DELAY);
  },
  { deep: true }
);
check();
if (flowId.value) loadMeta();

onBeforeUnmount(() => {
  stopMeta();
  clearTimeout(timer);
  clearTimeout(copiedTimer);
});

const categoryOptions = computed(() =>
  CATEGORIES.map(item => ({
    value: item,
    label: t(`WHATSAPP_FLOWS.CATEGORIES.${item}`),
  }))
);

const missing = computed(() => ({
  name: !name.value.trim(),
}));
const showMissing = key => triedToSave.value && missing.value[key];

const goToScreen = index => {
  currentScreen.value = index;
  selected.value = null;
};
const addScreen = () => {
  definition.screens.push(newScreen(definition.screens.length + 1));
  goToScreen(definition.screens.length - 1);
};
const removeScreen = index => {
  definition.screens.splice(index, 1);
  goToScreen(Math.min(currentScreen.value, definition.screens.length - 1));
};
// The tabs are dragged with the mouse or a finger; the keyboard moves the focused tab with Alt/Ctrl + ← →.
// Each screen gets a key of its own so the tabs keep their identity while they are reordered.
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

const reorderScreens = ordered => {
  const selectedScreen = toRaw(screen.value);
  definition.screens.splice(0, definition.screens.length, ...ordered);
  currentScreen.value = definition.screens.findIndex(
    item => toRaw(item) === selectedScreen
  );
};

const focusTab = index => {
  nextTick(() => {
    tabsRef.value?.$el?.querySelectorAll('[role="tab"]')[index]?.focus();
  });
};

const moveTab = (index, step) => {
  const target = index + step;
  if (target < 0 || target >= definition.screens.length) return;
  const ordered = [...definition.screens];
  const [moved] = ordered.splice(index, 1);
  ordered.splice(target, 0, moved);
  reorderScreens(ordered);
  announcement.value = t('WHATSAPP_FLOWS.EDITOR.TAB_MOVED', {
    n: target + 1,
    total: ordered.length,
  });
  focusTab(target);
};

const onTabKeydown = (event, index) => {
  if (!(event.altKey || event.ctrlKey)) return;
  if (event.key !== 'ArrowLeft' && event.key !== 'ArrowRight') return;
  event.preventDefault();
  moveTab(index, event.key === 'ArrowLeft' ? -1 : 1);
};

const tabTitle = (item, index) =>
  t('WHATSAPP_FLOWS.EDITOR.SCREEN_TAB', {
    n: index + 1,
    title: item.title || t('WHATSAPP_FLOWS.EDITOR.SCREEN_UNTITLED'),
  });

const addBlock = item => {
  const created = newBlock(item.type, definition);
  if (item.input) created.input = item.input;
  screen.value.blocks.push(created);
  touch(`screens.${currentScreen.value}.blocks`);
  selected.value = screen.value.blocks.length - 1;
};
const updateBlock = value => {
  const previous = screen.value.blocks[selected.value];
  Object.keys(value).forEach(key => {
    if (JSON.stringify(value[key]) !== JSON.stringify(previous[key]))
      touch(`screens.${currentScreen.value}.blocks.${selected.value}.${key}`);
  });
  screen.value.blocks.splice(selected.value, 1, value);
};
const removeBlock = index => {
  touch(`screens.${currentScreen.value}.blocks`);
  screen.value.blocks.splice(index, 1);
  selected.value = null;
};
const moveBlock = (index, step) => {
  const { blocks } = screen.value;
  const target = index + step;
  if (target < 0 || target >= blocks.length) return;
  const [moved] = blocks.splice(index, 1);
  blocks.splice(target, 0, moved);
  selected.value = target;
};

const flowJsonText = computed(() =>
  flowJson.value ? JSON.stringify(flowJson.value, null, 2) : ''
);

const copyJson = async () => {
  try {
    await navigator.clipboard.writeText(flowJsonText.value);
  } catch {
    return;
  }
  jsonCopied.value = true;
  clearTimeout(copiedTimer);
  copiedTimer = setTimeout(() => {
    jsonCopied.value = false;
  }, 2000);
};

const openJson = () => {
  jsonCopied.value = false;
  jsonDialog.value?.open();
};

const errorText = error => {
  const key = `WHATSAPP_FLOWS.ERRORS.${error.code}`;
  return te(key) ? t(key, error.details || {}) : error.code;
};

const save = async () => {
  triedToSave.value = true;
  if (!categories.value.length) categories.value = ['OTHER'];
  if (Object.values(missing.value).some(Boolean)) return;
  isSaving.value = true;
  const payload = {
    name: name.value.trim(),
    categories: categories.value,
    definition: JSON.parse(JSON.stringify(definition)),
  };
  try {
    const { data } = flowId.value
      ? await props.api.update(flowId.value, payload)
      : await props.api.create(payload);
    flowId.value = data.id;
    savedUnpublishedChanges.value = data.unpublished_changes;
    metaUnpublishedChanges.value = data.unpublished_changes;
    savedSnapshot.value = snapshot();
    useAlert(t('WHATSAPP_FLOWS.EDITOR.SAVED'));
    emit('saved', data);
    loadMeta();
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('WHATSAPP_FLOWS.EDITOR.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

const openPublish = async () => {
  triedToSave.value = true;
  await loadMeta();
  publishDialog.value?.open();
};

const startPublish = async () => {
  try {
    await publishToMeta();
  } catch (error) {
    stopMeta();
    publishDialog.value?.close();
    useAlert(
      error?.response?.data?.error === 'no_cloud_channels'
        ? t('WHATSAPP_FLOWS.META.NO_CLOUD')
        : t('WHATSAPP_FLOWS.META.PUBLISH_ERROR')
    );
  }
};

const retryPublish = async wabaId => {
  try {
    await retryMeta(wabaId);
  } catch {
    stopMeta();
    useAlert(t('WHATSAPP_FLOWS.META.PUBLISH_ERROR'));
  }
};

const openTest = async () => {
  await loadMeta();
  testDialog.value?.open();
};
const onMenuAction = item => {
  if (item.action === 'try') isTrying.value = !isTrying.value;
  else if (item.action === 'test') openTest();
  else openJson();
};

const sendTest = ({ channelId, phoneNumber }) =>
  props.api.test(flowId.value, { channelId, phoneNumber });

defineExpose({ save });
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="flow-builder">
    <header
      class="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-n-weak"
    >
      <div class="flex items-center min-w-0 gap-3">
        <Button
          type="button"
          ghost
          slate
          sm
          icon="i-lucide-arrow-left"
          :aria-label="$t('WHATSAPP_FLOWS.EDITOR.BACK_TO_LIST')"
          data-testid="flow-editor-back"
          @click="emit('back')"
        />
        <div class="min-w-0">
          <h1 class="m-0 text-heading-2 text-n-slate-12 truncate max-w-64">
            {{ name || $t('WHATSAPP_FLOWS.EDITOR.NAME_PLACEHOLDER') }}
          </h1>
          <p class="m-0 text-xs text-n-slate-11" data-testid="flow-save-state">
            {{
              $t(
                dirty || !flowId
                  ? 'WHATSAPP_FLOWS.EDITOR.UNSAVED'
                  : 'WHATSAPP_FLOWS.EDITOR.SAVE_STATE'
              )
            }}
          </p>
        </div>
        <MenuPopover panel-class="w-72 max-w-[calc(100vw-2rem)]">
          <template #trigger="{ toggle }">
            <Button
              type="button"
              slate
              faded
              sm
              trailing-icon
              icon="i-lucide-chevron-down"
              :label="statusLabel"
              data-testid="flow-editor-status"
              :disabled="isTrying"
              @click="toggle"
            />
          </template>
          <template #content>
            <div class="py-2" data-testid="flow-meta-status">
              <p
                v-if="unpublishedChanges"
                class="m-0 mb-3 text-xs text-n-amber-11"
                data-testid="flow-unpublished-banner"
              >
                {{ $t('WHATSAPP_FLOWS.META.UNPUBLISHED_CHANGES_BANNER') }}
              </p>
              <FlowPublicationBadges
                v-if="hasCloud"
                :rows="metaRows"
                detailed
                can-retry
                :sending="isPublishing"
                @retry="retryPublish"
              />
              <p v-else class="m-0 text-xs text-n-slate-11">
                {{ $t('WHATSAPP_FLOWS.META.NO_CLOUD') }}
              </p>
            </div>
          </template>
        </MenuPopover>
        <span
          v-if="visibleErrors.length"
          class="text-xs text-n-amber-11"
          data-testid="flow-editor-state"
          >{{
            $t('WHATSAPP_FLOWS.EDITOR.ERRORS_COUNT', {
              n: visibleErrors.length,
            })
          }}</span
        >
      </div>
      <div class="flex items-center gap-2">
        <div class="w-44" data-testid="flow-editor-category">
          <ComboBox
            v-model="categories"
            multiple
            teleport
            :options="categoryOptions"
            :aria-label="$t('WHATSAPP_FLOWS.NEW.CATEGORIES')"
            :placeholder="$t('WHATSAPP_FLOWS.CATEGORIES.OTHER')"
            data-testid="flow-category-select"
            :disabled="isTrying"
          />
        </div>
        <MenuPopover
          :menu-items="actionItems"
          :label="$t('WHATSAPP_FLOWS.EDITOR.ACTIONS')"
          @action="onMenuAction"
        >
          <template #trigger="{ toggle }">
            <Button
              type="button"
              ghost
              slate
              sm
              trailing-icon
              icon="i-lucide-chevron-down"
              :label="$t('WHATSAPP_FLOWS.EDITOR.ACTIONS')"
              data-testid="flow-actions"
              @click="toggle"
            />
          </template>
        </MenuPopover>
        <Button
          type="button"
          slate
          sm
          :label="$t('WHATSAPP_FLOWS.EDITOR.SAVE')"
          :is-loading="isSaving"
          :disabled="isSaving || isTrying"
          data-testid="flow-editor-save"
          @click="save"
        />
        <Button
          v-if="hasCloud"
          type="button"
          sm
          icon="i-lucide-send"
          :label="$t('WHATSAPP_FLOWS.META.PUBLISH')"
          :disabled="metaBlocked || isPublishing || isTrying"
          :title="metaHint"
          data-testid="flow-publish-open"
          @click="openPublish"
        />
      </div>
    </header>

    <FlowPublishDialog
      ref="publishDialog"
      :rows="metaRows"
      :busy="isPublishing"
      @publish="startPublish"
      @retry="retryPublish"
    />
    <FlowTestDialog ref="testDialog" :wabas="metaWabas" :send="sendTest" />

    <Dialog
      ref="jsonDialog"
      width="3xl"
      body-scroll
      :title="$t('WHATSAPP_FLOWS.EDITOR.JSON_TITLE')"
      :description="$t('WHATSAPP_FLOWS.EDITOR.JSON_DESCRIPTION')"
      data-testid="flow-json-dialog"
    >
      <pre
        class="p-3 m-0 overflow-auto font-mono text-xs border rounded-lg max-h-[60vh] border-n-weak bg-n-alpha-2 text-n-slate-12"
        tabindex="0"
        data-testid="flow-json"
        >{{ flowJsonText }}</pre
      >
      <template #footer>
        <div class="flex items-center justify-end gap-3">
          <Button
            type="button"
            slate
            faded
            :label="$t('WHATSAPP_FLOWS.EDITOR.JSON_CLOSE')"
            data-testid="flow-json-close"
            @click="jsonDialog?.close()"
          />
          <Button
            type="button"
            :icon="jsonCopied ? 'i-lucide-check' : 'i-lucide-copy'"
            :label="
              jsonCopied
                ? $t('WHATSAPP_FLOWS.EDITOR.JSON_COPIED')
                : $t('WHATSAPP_FLOWS.EDITOR.JSON_COPY')
            "
            data-testid="flow-json-copy"
            @click="copyJson"
          />
        </div>
      </template>
    </Dialog>

    <div
      class="flex flex-wrap items-center gap-2"
      data-testid="flow-screen-tabs"
      :inert="isTrying"
      :class="{ 'opacity-50': isTrying }"
    >
      <span id="flow-tabs-hint" class="sr-only">
        {{ $t('WHATSAPP_FLOWS.EDITOR.TAB_HINT') }}
      </span>
      <span class="sr-only" role="status" aria-live="polite">
        {{ announcement }}
      </span>
      <Draggable
        ref="tabsRef"
        :model-value="definition.screens"
        :item-key="screenKey"
        class="flex flex-wrap items-center gap-2"
        role="tablist"
        aria-describedby="flow-tabs-hint"
        v-bind="DRAG_OPTIONS"
        data-testid="flow-screen-draggable"
        @update:model-value="reorderScreens"
      >
        <template #item="{ element: item, index }">
          <div
            class="flex items-center gap-1 py-1 text-sm font-semibold border-[1.5px] rounded-full ps-3.5 pe-1.5 cursor-grab select-none"
            :class="
              index === currentScreen
                ? 'border-n-brand bg-n-brand/10 text-n-blue-text'
                : 'border-n-weak bg-n-solid-1 text-n-slate-12'
            "
            role="tab"
            tabindex="0"
            aria-keyshortcuts="Alt+ArrowLeft Alt+ArrowRight"
            :aria-selected="index === currentScreen"
            data-testid="flow-screen-tab"
            @click="goToScreen(index)"
            @keydown.enter.self="goToScreen(index)"
            @keydown="onTabKeydown($event, index)"
          >
            <span class="truncate max-w-40">{{ tabTitle(item, index) }}</span>
            <button
              v-if="definition.screens.length > 1"
              type="button"
              class="grid px-1.5 flow-tab-remove text-n-slate-11 hover:text-n-ruby-11 place-items-center"
              :aria-label="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_SCREEN')"
              data-testid="flow-screen-remove"
              @click.stop="removeScreen(index)"
            >
              <span class="i-lucide-x size-3.5" />
            </button>
          </div>
        </template>
      </Draggable>
      <button
        type="button"
        class="px-3.5 py-1 text-sm font-semibold border-[1.5px] border-dashed rounded-full border-n-weak text-n-slate-11 hover:border-n-brand"
        data-testid="flow-screen-add"
        @click="addScreen"
      >
        {{ $t('WHATSAPP_FLOWS.EDITOR.ADD_SCREEN_TAB') }}
      </button>
    </div>

    <div
      class="grid items-start gap-4 min-[1100px]:grid-cols-[16rem_minmax(0,1fr)_22.5rem] min-[1360px]:grid-cols-[19rem_minmax(0,1fr)_27rem]"
    >
      <section
        class="min-w-0 pe-3 border-e border-n-weak"
        data-testid="flow-palette"
        :inert="isTrying"
        :class="{ 'opacity-50': isTrying }"
      >
        <h2
          class="mb-3 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
        >
          {{ $t('WHATSAPP_FLOWS.EDITOR.ADD_PANEL') }}
        </h2>
        <div
          v-for="group in PALETTE"
          :key="group.group"
          class="grid grid-cols-2 gap-1"
        >
          <p class="sr-only">
            {{ $t(`WHATSAPP_FLOWS.EDITOR.GROUPS.${group.group}`) }}
          </p>
          <button
            v-for="item in group.items"
            :key="item.id"
            type="button"
            class="flex items-center gap-2 px-2 py-2 text-sm text-start rounded-lg leading-tight text-n-slate-12 hover:bg-n-alpha-2"
            :data-testid="`flow-add-${item.id}`"
            @click="addBlock(item)"
          >
            <span
              class="grid size-5 shrink-0 place-items-center text-n-slate-11"
            >
              <span :class="item.icon" class="size-3.5" />
            </span>
            {{ $t(`WHATSAPP_FLOWS.BLOCKS.${item.id}`) }}
          </button>
        </div>
      </section>

      <div class="grid gap-4">
        <FlowPhoneSimulator
          v-if="isTrying"
          :definition="definition"
          :flow-name="name"
          :attributes="attributes"
          @edit="isTrying = false"
        />
        <FlowPhoneCanvas
          v-else
          :definition="definition"
          :screen-index="currentScreen"
          :selected="selected"
          @select="selected = $event"
          @remove="removeBlock"
          @move="moveBlock"
        />
      </div>

      <aside
        class="flex flex-col min-w-0 gap-5 ps-4 border-s border-n-weak"
        data-testid="flow-properties"
        :inert="isTrying"
        :class="{ 'opacity-50': isTrying }"
      >
        <div
          v-if="block"
          class="grid gap-3 grid-cols-[minmax(0,1fr)]"
          data-testid="flow-block-props"
        >
          <h2
            class="m-0 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{
              $t('WHATSAPP_FLOWS.EDITOR.FIELD_PROPS', {
                name: $t(`WHATSAPP_FLOWS.BLOCKS.${block.type}`),
              })
            }}
          </h2>
          <FlowBlockEditor
            :key="`${currentScreen}-${selected}`"
            :model-value="block"
            :attributes="attributes"
            :definition="definition"
            :screen-index="currentScreen"
            :block-index="selected"
            :errors="grouped.block[`${currentScreen}.${selected}`] || []"
            @update:model-value="updateBlock"
          />
        </div>

        <div
          v-else
          class="grid gap-3 grid-cols-[minmax(0,1fr)]"
          data-testid="flow-form-props"
        >
          <ul
            v-if="grouped.form.length"
            class="grid gap-1 m-0 text-xs list-none text-n-ruby-11"
          >
            <li v-for="error in grouped.form" :key="error.code">
              {{ errorText(error) }}
            </li>
          </ul>
          <p class="m-0 text-sm text-n-slate-11">
            {{ $t('WHATSAPP_FLOWS.EDITOR.PICK_HINT') }}
          </p>
        </div>
        <div class="grid gap-3">
          <h2
            class="m-0 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ $t('WHATSAPP_FLOWS.EDITOR.FLOW_PROPS') }}
          </h2>
          <Input
            v-model="name"
            size="sm"
            :label="$t('WHATSAPP_FLOWS.EDITOR.NAME')"
            :placeholder="$t('WHATSAPP_FLOWS.EDITOR.NAME_PLACEHOLDER')"
            :message="
              showMissing('name')
                ? $t('WHATSAPP_FLOWS.EDITOR.NAME_REQUIRED')
                : ''
            "
            :message-type="showMissing('name') ? 'error' : 'info'"
            data-testid="flow-editor-name"
          />
        </div>
        <div v-if="screen" class="grid gap-3 grid-cols-[minmax(0,1fr)]">
          <h2
            class="m-0 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ $t('WHATSAPP_FLOWS.EDITOR.SCREEN_PROPS') }}
          </h2>
          <Input
            v-model="screen.title"
            size="sm"
            :label="$t('WHATSAPP_FLOWS.EDITOR.SCREEN_TITLE')"
            :max-length="LIMITS.screenTitle"
            data-testid="flow-screen-title"
            @update:model-value="touch(`screens.${currentScreen}.title`)"
          />
          <Input
            v-model="screen.button"
            size="sm"
            :label="$t('WHATSAPP_FLOWS.EDITOR.BUTTON')"
            :placeholder="
              currentScreen === definition.screens.length - 1
                ? $t('WHATSAPP_FLOWS.EDITOR.BUTTON_LAST')
                : $t('WHATSAPP_FLOWS.EDITOR.BUTTON_NEXT')
            "
            :max-length="LIMITS.footer"
            data-testid="flow-screen-button"
            @update:model-value="touch(`screens.${currentScreen}.button`)"
          />
          <ul
            v-if="screenErrors"
            class="grid gap-1 m-0 text-xs list-none text-n-ruby-11"
            data-testid="flow-screen-errors"
          >
            <li v-for="error in screenErrors" :key="error.code">
              {{ errorText(error) }}
            </li>
          </ul>
        </div>
      </aside>
    </div>
  </div>
</template>
