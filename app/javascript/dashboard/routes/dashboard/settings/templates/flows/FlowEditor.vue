<script setup>
// The form builder: the screens and blocks on the left, the form in a phone on the right (always the screen being
// edited), the mistakes Meta would refuse shown while typing, and the draft saved on demand.
import { computed, onBeforeUnmount, reactive, ref, watch } from 'vue';
import { useI18n } from 'vue-i18n';
import { vOnClickOutside } from '@vueuse/components';

import { useAlert } from 'dashboard/composables';
import WhatsappFlowsAPI from 'dashboard/api/whatsappFlows';
import Button from 'dashboard/components-next/button/Button.vue';
import DropdownMenu from 'dashboard/components-next/dropdown-menu/DropdownMenu.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import FlowBlockEditor from './FlowBlockEditor.vue';
import FlowPhonePreview from './FlowPhonePreview.vue';
import {
  BLOCK_TYPES,
  CATEGORIES,
  LIMITS,
  groupErrors,
  newBlock,
  newScreen,
} from './flowDefinition';

const props = defineProps({
  // { id (null while it is new), name, categories, definition }
  flow: { type: Object, required: true },
});

const emit = defineEmits(['back', 'saved']);

const { t, te } = useI18n();

const VALIDATE_DELAY = 500;

const name = ref(props.flow.name || '');
const categories = ref([...(props.flow.categories || [])]);
const definition = reactive(JSON.parse(JSON.stringify(props.flow.definition)));
const flowId = ref(props.flow.id || null);
const isSaving = ref(false);
const isChecking = ref(false);
const dirty = ref(!props.flow.id);
const errors = ref([]);
const flowJson = ref(null);
const showJson = ref(false);
const openMenu = ref(null);
const previewRef = ref(null);
let timer = null;
let controller = null;

const grouped = computed(() => groupErrors(errors.value));
const isReady = computed(
  () => !errors.value.length && definition.screens.length > 0
);

const check = async () => {
  controller?.abort();
  controller = new AbortController();
  isChecking.value = true;
  try {
    const { data } = await WhatsappFlowsAPI.validate(
      JSON.parse(JSON.stringify(definition)),
      { signal: controller.signal }
    );
    errors.value = data.errors || [];
    flowJson.value = data.flow_json;
  } catch (error) {
    if (error?.code !== 'ERR_CANCELED') errors.value = [];
  } finally {
    isChecking.value = false;
  }
};

watch(
  definition,
  () => {
    dirty.value = true;
    clearTimeout(timer);
    timer = setTimeout(check, VALIDATE_DELAY);
  },
  { deep: true }
);
watch([name, categories], () => {
  dirty.value = true;
});
check();

onBeforeUnmount(() => {
  clearTimeout(timer);
  controller?.abort();
});

const toggleCategory = category => {
  categories.value = categories.value.includes(category)
    ? categories.value.filter(item => item !== category)
    : [...categories.value, category];
};

const addScreen = () => {
  definition.screens.push(newScreen());
};
const removeScreen = index => {
  definition.screens.splice(index, 1);
};
const moveScreen = (index, step) => {
  const target = index + step;
  if (target < 0 || target >= definition.screens.length) return;
  const [moved] = definition.screens.splice(index, 1);
  definition.screens.splice(target, 0, moved);
};

const blockMenu = computed(() =>
  ['text', 'answer', 'file'].map(group => ({
    title: t(`WHATSAPP_FLOWS.EDITOR.GROUPS.${group}`),
    items: BLOCK_TYPES.filter(item => item.group === group).map(item => ({
      label: t(`WHATSAPP_FLOWS.BLOCKS.${item.type}`),
      icon: item.icon,
      action: 'add',
      value: item.type,
    })),
  }))
);

const addBlock = (screenIndex, type) => {
  definition.screens[screenIndex].blocks.push(newBlock(type, definition));
  openMenu.value = null;
  previewRef.value?.goTo(screenIndex);
};
const updateBlock = (screenIndex, blockIndex, block) => {
  definition.screens[screenIndex].blocks.splice(blockIndex, 1, block);
};
const removeBlock = (screenIndex, blockIndex) => {
  definition.screens[screenIndex].blocks.splice(blockIndex, 1);
};
const moveBlock = (screenIndex, blockIndex, step) => {
  const { blocks } = definition.screens[screenIndex];
  const target = blockIndex + step;
  if (target < 0 || target >= blocks.length) return;
  const [moved] = blocks.splice(blockIndex, 1);
  blocks.splice(target, 0, moved);
};

const formErrorText = error => {
  const key = `WHATSAPP_FLOWS.ERRORS.${error.code}`;
  return te(key) ? t(key, error.details || {}) : error.code;
};

const save = async () => {
  if (!name.value.trim()) {
    useAlert(t('WHATSAPP_FLOWS.EDITOR.NAME_REQUIRED'));
    return;
  }
  isSaving.value = true;
  const payload = {
    name: name.value.trim(),
    categories: categories.value,
    definition: JSON.parse(JSON.stringify(definition)),
  };
  try {
    const { data } = flowId.value
      ? await WhatsappFlowsAPI.update(flowId.value, payload)
      : await WhatsappFlowsAPI.create(payload);
    flowId.value = data.id;
    dirty.value = false;
    useAlert(t('WHATSAPP_FLOWS.EDITOR.SAVED'));
    emit('saved', data);
  } catch (error) {
    useAlert(
      error?.response?.data?.message || t('WHATSAPP_FLOWS.EDITOR.SAVE_ERROR')
    );
  } finally {
    isSaving.value = false;
  }
};

defineExpose({ save });
</script>

<template>
  <div class="flex flex-col gap-5" data-testid="flow-editor">
    <div class="flex flex-wrap items-center justify-between gap-3">
      <Button
        type="button"
        ghost
        slate
        sm
        icon="i-lucide-arrow-left"
        :label="$t('WHATSAPP_FLOWS.EDITOR.BACK')"
        data-testid="flow-editor-back"
        @click="emit('back')"
      />
      <div class="flex items-center gap-3">
        <span
          class="inline-flex px-2 py-0.5 text-xs font-medium rounded-md"
          :class="
            isReady
              ? 'bg-n-teal-3 text-n-teal-11'
              : 'bg-n-amber-3 text-n-amber-11'
          "
          data-testid="flow-editor-state"
        >
          {{
            isReady
              ? $t('WHATSAPP_FLOWS.EDITOR.READY')
              : $t('WHATSAPP_FLOWS.EDITOR.TO_FIX', { n: errors.length })
          }}
        </span>
        <Button
          type="button"
          :label="$t('WHATSAPP_FLOWS.EDITOR.SAVE')"
          :is-loading="isSaving"
          :disabled="isSaving || !dirty"
          data-testid="flow-editor-save"
          @click="save"
        />
      </div>
    </div>

    <div class="grid gap-6 lg:grid-cols-[minmax(0,1fr)_21rem]">
      <div class="flex flex-col gap-5">
        <div class="grid gap-3 p-4 border rounded-xl border-n-weak">
          <Input
            v-model="name"
            :label="$t('WHATSAPP_FLOWS.EDITOR.NAME')"
            :placeholder="$t('WHATSAPP_FLOWS.EDITOR.NAME_PLACEHOLDER')"
            data-testid="flow-editor-name"
          />
          <div class="grid gap-1">
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t('WHATSAPP_FLOWS.EDITOR.CATEGORIES') }}
            </span>
            <div class="flex flex-wrap gap-2">
              <Button
                v-for="category in CATEGORIES"
                :key="category"
                type="button"
                xs
                :slate="!categories.includes(category)"
                :label="$t(`WHATSAPP_FLOWS.CATEGORIES.${category}`)"
                @click="toggleCategory(category)"
              />
            </div>
          </div>
          <ul
            v-if="grouped.form.length"
            class="grid gap-1 text-xs text-n-ruby-11"
          >
            <li v-for="error in grouped.form" :key="error.code">
              {{ formErrorText(error) }}
            </li>
          </ul>
        </div>

        <section
          v-for="(screen, screenIndex) in definition.screens"
          :key="screenIndex"
          class="grid gap-3 p-4 border rounded-xl border-n-weak"
          data-testid="flow-screen"
          @focusin="previewRef?.goTo(screenIndex)"
        >
          <div class="flex items-center gap-2">
            <span
              class="inline-flex items-center justify-center text-xs font-medium rounded-full size-6 bg-n-alpha-2 text-n-slate-12"
            >
              {{ screenIndex + 1 }}
            </span>
            <Input
              v-model="screen.title"
              class="flex-1"
              size="sm"
              :max-length="LIMITS.screenTitle"
              :placeholder="$t('WHATSAPP_FLOWS.EDITOR.SCREEN_TITLE')"
              data-testid="flow-screen-title"
            />
            <Button
              type="button"
              ghost
              slate
              xs
              icon="i-lucide-arrow-up"
              :disabled="screenIndex === 0"
              :aria-label="$t('WHATSAPP_FLOWS.EDITOR.MOVE_UP')"
              @click="moveScreen(screenIndex, -1)"
            />
            <Button
              type="button"
              ghost
              slate
              xs
              icon="i-lucide-arrow-down"
              :disabled="screenIndex === definition.screens.length - 1"
              :aria-label="$t('WHATSAPP_FLOWS.EDITOR.MOVE_DOWN')"
              @click="moveScreen(screenIndex, 1)"
            />
            <Button
              type="button"
              ghost
              ruby
              xs
              icon="i-lucide-trash-2"
              :disabled="definition.screens.length <= 1"
              :aria-label="$t('WHATSAPP_FLOWS.EDITOR.REMOVE_SCREEN')"
              data-testid="flow-screen-remove"
              @click="removeScreen(screenIndex)"
            />
          </div>
          <ul
            v-if="grouped.screen[screenIndex]"
            class="grid gap-1 text-xs text-n-ruby-11"
          >
            <li v-for="error in grouped.screen[screenIndex]" :key="error.code">
              {{ formErrorText(error) }}
            </li>
          </ul>

          <FlowBlockEditor
            v-for="(block, blockIndex) in screen.blocks"
            :key="blockIndex"
            :model-value="block"
            :definition="definition"
            :screen-index="screenIndex"
            :block-index="blockIndex"
            :is-first="blockIndex === 0"
            :is-last="blockIndex === screen.blocks.length - 1"
            :errors="grouped.block[`${screenIndex}.${blockIndex}`] || []"
            @update:model-value="updateBlock(screenIndex, blockIndex, $event)"
            @remove="removeBlock(screenIndex, blockIndex)"
            @move="moveBlock(screenIndex, blockIndex, $event)"
          />

          <div
            v-on-click-outside="
              () => (openMenu === screenIndex ? (openMenu = null) : null)
            "
            class="relative"
          >
            <Button
              type="button"
              slate
              sm
              icon="i-lucide-plus"
              :label="$t('WHATSAPP_FLOWS.EDITOR.ADD_BLOCK')"
              data-testid="flow-block-add"
              @click="openMenu = openMenu === screenIndex ? null : screenIndex"
            />
            <DropdownMenu
              v-if="openMenu === screenIndex"
              :menu-sections="blockMenu"
              class="mt-1 min-w-56 max-h-72 overflow-y-auto top-full ltr:left-0 rtl:right-0"
              @action="item => addBlock(screenIndex, item.value)"
            />
          </div>

          <Input
            v-model="screen.button"
            size="sm"
            :label="$t('WHATSAPP_FLOWS.EDITOR.BUTTON')"
            :placeholder="
              screenIndex === definition.screens.length - 1
                ? $t('WHATSAPP_FLOWS.EDITOR.BUTTON_LAST')
                : $t('WHATSAPP_FLOWS.EDITOR.BUTTON_NEXT')
            "
            :max-length="LIMITS.footer"
            data-testid="flow-screen-button"
          />
        </section>

        <div>
          <Button
            type="button"
            slate
            sm
            icon="i-lucide-layout-panel-left"
            :label="$t('WHATSAPP_FLOWS.EDITOR.ADD_SCREEN')"
            data-testid="flow-screen-add"
            @click="addScreen"
          />
        </div>
      </div>

      <aside class="flex flex-col gap-3 lg:sticky lg:top-4 lg:self-start">
        <FlowPhonePreview ref="previewRef" :definition="definition" />
        <p class="text-xs text-center text-n-slate-11">
          {{ $t('WHATSAPP_FLOWS.EDITOR.PREVIEW_NOTE') }}
        </p>
        <div class="text-center">
          <Button
            type="button"
            ghost
            slate
            xs
            :label="
              showJson
                ? $t('WHATSAPP_FLOWS.EDITOR.HIDE_JSON')
                : $t('WHATSAPP_FLOWS.EDITOR.SHOW_JSON')
            "
            :disabled="!flowJson"
            data-testid="flow-json-toggle"
            @click="showJson = !showJson"
          />
          <span v-if="isChecking" class="ml-2 text-xs text-n-slate-11">
            {{ $t('WHATSAPP_FLOWS.EDITOR.CHECKING') }}
          </span>
        </div>
        <pre
          v-if="showJson && flowJson"
          class="p-3 overflow-auto text-xs border rounded-lg max-h-72 border-n-weak bg-n-alpha-2 text-n-slate-12"
          data-testid="flow-json"
          >{{ JSON.stringify(flowJson, null, 2) }}</pre
        >
      </aside>
    </div>
  </div>
</template>
