<script setup>
// The flow builder as a full page: the screens as tabs, the blocks to add on the left, the phone in the middle (blocks
// are edited by clicking them there) and the settings of the selected screen and block on the right. The mistakes Meta
// would refuse are shown while typing and the draft is saved on demand. A new flow is built in this same page: its
// name is editable in the header; categories live in Flow settings. The creation dialog chooses the starting content.
import {
  computed,
  nextTick,
  onBeforeUnmount,
  reactive,
  ref,
  toRaw,
  watch,
} from 'vue';
import { useEventListener } from '@vueuse/core';
import { useI18n } from 'vue-i18n';
import { useStore } from 'vuex';

import { useAlert } from 'dashboard/composables';
import { useAbortableRequest } from 'dashboard/composables/useAbortableRequest';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import InfoChip from 'dashboard/components-next/ListCard/InfoChip.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import MenuPopover from 'dashboard/components-next/dropdown-menu/MenuPopover.vue';
import FlowBlockEditor from './FlowBlockEditor.vue';
import FlowStructurePanel from './FlowStructurePanel.vue';
import FlowPhoneCanvas from './FlowPhoneCanvas.vue';
import FlowPhoneSimulator from './FlowPhoneSimulator.vue';
import FlowPublicationBadges from './FlowPublicationBadges.vue';
import FlowPublishDialog from './FlowPublishDialog.vue';
import FlowTestDialog from './FlowTestDialog.vue';
import { useFlowPublications } from './useFlowPublications';
import {
  CATEGORIES,
  LIMITS,
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
// The official starting templates store these button labels in their definition.
const TEMPLATE_BUTTON_LABELS = ['Continuar', 'Enviar'];
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
const jsonCopied = ref(false);
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
const leaveDialog = ref(null);
const removeScreenDialog = ref(null);
const pendingScreen = ref(null);
const screenTitleInput = ref(null);
const structurePanel = ref(null);
let resolveLeave = null;

// What was last saved (or loaded); anything different is a change Meta would not see yet.
const snapshot = () =>
  JSON.stringify([name.value.trim(), categories.value, definition]);
const savedSnapshot = ref(snapshot());
const dirty = computed(() => snapshot() !== savedSnapshot.value);
const requestLeave = () => {
  if (!dirty.value && flowId.value) return Promise.resolve(true);
  if (resolveLeave) return Promise.resolve(false);
  leaveDialog.value?.open();
  return new Promise(resolve => {
    resolveLeave = resolve;
  });
};
const finishLeave = leave => {
  resolveLeave?.(leave);
  resolveLeave = null;
  leaveDialog.value?.close();
};
const goBack = () => emit('back');
useEventListener(window, 'beforeunload', event => {
  if (!dirty.value && flowId.value) return;
  event.preventDefault();
  event.returnValue = '';
});

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
  resolveLeave?.(false);
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
const normalizeScreenButtons = () => {
  const next = t('WHATSAPP_FLOWS.EDITOR.BUTTON_NEXT');
  const last = t('WHATSAPP_FLOWS.EDITOR.BUTTON_LAST');
  const defaults = new Set([next, last, ...TEMPLATE_BUTTON_LABELS]);
  definition.screens.forEach((item, index) => {
    if (defaults.has(item.button)) {
      item.button = index === definition.screens.length - 1 ? last : next;
    }
  });
};
const addScreen = () => {
  definition.screens.push(
    newScreen(
      definition.screens.length + 1,
      t('WHATSAPP_FLOWS.EDITOR.BUTTON_LAST')
    )
  );
  normalizeScreenButtons();
  goToScreen(definition.screens.length - 1);
};
const removeScreen = index => {
  pendingScreen.value = definition.screens[index];
  removeScreenDialog.value?.open();
};
const confirmRemoveScreen = () => {
  const index = definition.screens.indexOf(pendingScreen.value);
  if (index < 0 || definition.screens.length === 1) return;
  const active = toRaw(screen.value);
  definition.screens.splice(index, 1);
  normalizeScreenButtons();
  const activeIndex = definition.screens.findIndex(
    item => toRaw(item) === active
  );
  if (activeIndex < 0)
    goToScreen(Math.min(index, definition.screens.length - 1));
  else currentScreen.value = activeIndex;
  removeScreenDialog.value?.close();
};
const restoreScreenFocus = () => {
  const index = definition.screens.indexOf(pendingScreen.value);
  structurePanel.value?.focusScreen(index >= 0 ? index : currentScreen.value);
  pendingScreen.value = null;
};
const renameScreen = index => {
  goToScreen(index);
  nextTick(() => {
    const input = screenTitleInput.value?.$el?.querySelector('input');
    input?.focus();
    input?.select();
  });
};
const reorderScreens = ordered => {
  const selectedScreen = toRaw(screen.value);
  definition.screens.splice(0, definition.screens.length, ...ordered);
  normalizeScreenButtons();
  currentScreen.value = definition.screens.findIndex(
    item => toRaw(item) === selectedScreen
  );
};

const blockKeys = new WeakMap();
let blockKeyCount = 0;
const blockKey = item => {
  const raw = toRaw(item);
  if (!blockKeys.has(raw)) {
    blockKeyCount += 1;
    blockKeys.set(raw, blockKeyCount);
  }
  return blockKeys.get(raw);
};
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
  if (previous.key && value.key && previous.key !== value.key) {
    definition.screens.forEach(item =>
      item.blocks.forEach(candidate => {
        if (candidate.visible_when?.key === previous.key)
          candidate.visible_when.key = value.key;
      })
    );
  }
  blockKeys.set(toRaw(value), blockKey(previous));
  screen.value.blocks.splice(selected.value, 1, value);
};
const removeBlock = index => {
  const active = block.value && toRaw(block.value);
  touch(`screens.${currentScreen.value}.blocks`);
  screen.value.blocks.splice(index, 1);
  const activeIndex = active
    ? screen.value.blocks.findIndex(item => toRaw(item) === active)
    : -1;
  selected.value = activeIndex < 0 ? null : activeIndex;
};
const reorderBlocks = ordered => {
  const active = block.value && toRaw(block.value);
  screen.value.blocks.splice(0, screen.value.blocks.length, ...ordered);
  const index = active
    ? screen.value.blocks.findIndex(item => toRaw(item) === active)
    : -1;
  selected.value = index < 0 ? null : index;
  touch(`screens.${currentScreen.value}.blocks`);
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
    categories: [...categories.value],
    definition: JSON.parse(JSON.stringify(definition)),
  };
  const submittedSnapshot = JSON.stringify([
    payload.name,
    payload.categories,
    payload.definition,
  ]);
  try {
    const { data } = flowId.value
      ? await props.api.update(flowId.value, payload)
      : await props.api.create(payload);
    flowId.value = data.id;
    savedUnpublishedChanges.value = data.unpublished_changes;
    metaUnpublishedChanges.value = data.unpublished_changes;
    savedSnapshot.value = submittedSnapshot;
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

defineExpose({ save, requestLeave });
</script>

<template>
  <div class="flex flex-col gap-4" data-testid="flow-builder">
    <header
      class="flex flex-wrap items-center justify-between gap-3 pb-3 border-b border-n-weak"
    >
      <div class="flex items-center min-w-0 gap-3">
        <Button
          type="button"
          intent="tertiary"
          sm
          icon="i-lucide-arrow-left"
          :aria-label="$t('WHATSAPP_FLOWS.EDITOR.BACK_TO_LIST')"
          data-testid="flow-editor-back"
          @click="goBack"
        />
        <div class="min-w-0">
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
            :disabled="isTrying"
            class="w-60 max-w-full"
            data-testid="flow-editor-name"
          />
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
        <InfoChip>{{ statusLabel }}</InfoChip>
        <MenuPopover panel-class="w-72 max-w-[calc(100vw-2rem)]">
          <template #trigger="{ toggle }">
            <Button
              type="button"
              intent="tertiary"
              sm
              icon="i-lucide-info"
              :label="$t('WHATSAPP_FLOWS.META.STATUS_TITLE')"
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
        <MenuPopover
          :menu-items="actionItems"
          :label="$t('WHATSAPP_FLOWS.EDITOR.ADVANCED')"
          @action="onMenuAction"
        >
          <template #trigger="{ toggle }">
            <Button
              type="button"
              intent="tertiary"
              sm
              trailing-icon
              icon="i-lucide-chevron-down"
              :label="$t('WHATSAPP_FLOWS.EDITOR.ADVANCED')"
              data-testid="flow-actions"
              @click="toggle"
            />
          </template>
        </MenuPopover>
        <Button
          type="button"
          intent="secondary"
          sm
          :icon="isTrying ? 'i-lucide-pencil' : 'i-lucide-play'"
          :label="
            isTrying
              ? $t('WHATSAPP_FLOWS.SIMULATOR.BACK_TO_EDIT')
              : $t('WHATSAPP_FLOWS.EDITOR.ACTION_TRY')
          "
          data-testid="flow-preview-try"
          @click="isTrying = !isTrying"
        />
        <Button
          type="button"
          intent="primary"
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
          intent="secondary"
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

    <Dialog
      ref="leaveDialog"
      type="alert"
      :title="$t('WHATSAPP_FLOWS.EDITOR.LEAVE_TITLE')"
      :description="$t('WHATSAPP_FLOWS.EDITOR.LEAVE_DESCRIPTION')"
      :confirm-button-label="$t('WHATSAPP_FLOWS.EDITOR.LEAVE_CONFIRM')"
      :cancel-button-label="$t('WHATSAPP_FLOWS.EDITOR.KEEP_EDITING')"
      data-testid="flow-leave-dialog"
      @confirm="finishLeave(true)"
      @close="finishLeave(false)"
    />
    <Dialog
      ref="removeScreenDialog"
      type="alert"
      :title="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_SCREEN_TITLE')"
      :description="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_SCREEN_DESCRIPTION')"
      :confirm-button-label="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_SCREEN')"
      data-testid="flow-remove-screen-dialog"
      @confirm="confirmRemoveScreen"
      @close="restoreScreenFocus"
    />
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
      class="grid items-start gap-4 min-[1200px]:grid-cols-[15rem_minmax(18rem,1fr)_20rem] min-[1440px]:grid-cols-[17rem_minmax(20rem,1fr)_23rem]"
    >
      <FlowStructurePanel
        ref="structurePanel"
        :screens="definition.screens"
        :screen-index="currentScreen"
        :selected="selected"
        :block-key="blockKey"
        :inert="isTrying"
        class="min-w-0 min-[1200px]:max-h-[calc(100dvh-12rem)] min-[1200px]:overflow-y-auto"
        :class="isTrying ? 'hidden opacity-50 min-[1200px]:flex' : ''"
        @select-screen="goToScreen"
        @add-screen="addScreen"
        @rename-screen="renameScreen"
        @remove-screen="removeScreen"
        @reorder-screens="reorderScreens"
        @select-block="selected = $event"
        @add-block="addBlock"
        @remove-block="removeBlock"
        @reorder-blocks="reorderBlocks"
      />

      <div class="grid min-w-0 gap-4">
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
        />
      </div>

      <aside
        class="flex flex-col min-w-0 gap-5 ps-4 border-s border-n-weak min-[1200px]:max-h-[calc(100dvh-12rem)] min-[1200px]:overflow-y-auto"
        data-testid="flow-properties"
        :inert="isTrying"
        :class="isTrying ? 'hidden opacity-50 min-[1200px]:flex' : ''"
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
            :key="blockKey(block)"
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
        <details v-if="!block" open class="group" data-testid="flow-settings">
          <summary
            class="flex items-center justify-between text-sm font-medium cursor-pointer text-n-slate-12"
          >
            {{ $t('WHATSAPP_FLOWS.EDITOR.FLOW_PROPS') }}
            <span class="i-lucide-chevron-down size-4 group-open:rotate-180" />
          </summary>
          <div class="grid gap-2 mt-3" data-testid="flow-editor-category">
            <label for="flow-category" class="text-sm text-n-slate-12">{{
              $t('WHATSAPP_FLOWS.NEW.CATEGORIES')
            }}</label>
            <ComboBox
              id="flow-category"
              v-model="categories"
              multiple
              teleport
              :options="categoryOptions"
              :aria-label="$t('WHATSAPP_FLOWS.NEW.CATEGORIES')"
              :placeholder="$t('WHATSAPP_FLOWS.EDITOR.CATEGORY')"
              data-testid="flow-category-select"
              :disabled="isTrying"
            />
            <p class="m-0 text-xs text-n-slate-11">
              {{ $t('WHATSAPP_FLOWS.NEW.CATEGORIES_HINT') }}
            </p>
          </div>
        </details>
        <div
          v-if="screen && !block"
          class="grid gap-3 grid-cols-[minmax(0,1fr)]"
        >
          <h2
            class="m-0 text-xs font-semibold tracking-wider uppercase text-n-slate-11"
          >
            {{ $t('WHATSAPP_FLOWS.EDITOR.SCREEN_PROPS') }}
          </h2>
          <Input
            ref="screenTitleInput"
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
