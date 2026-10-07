<script setup>
import { computed, ref } from 'vue';
import { useI18n } from 'vue-i18n';
import Dialog from 'dashboard/components-next/dialog/Dialog.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import Button from 'dashboard/components-next/button/Button.vue';
import ComboBox from 'dashboard/components-next/combobox/ComboBox.vue';
import {
  CATEGORIES,
  STARTING_POINTS,
  startingDefinition,
} from './flowDefinition';

const emit = defineEmits(['create', 'cancel']);
const { t } = useI18n();
const dialog = ref(null);
const name = ref('');
const categories = ref([]);
const template = ref('blank');
const triedToCreate = ref(false);
const templateList = ref(null);
let confirmed = false;
const templates = Object.keys(STARTING_POINTS);
const templateIcons = {
  blank: 'i-lucide-file',
  interests: 'i-lucide-list-checks',
  feedback: 'i-lucide-message-square',
  survey: 'i-lucide-clipboard-list',
  support: 'i-lucide-headset',
};
const categoryOptions = computed(() =>
  CATEGORIES.map(value => ({
    value,
    label: t(`WHATSAPP_FLOWS.CATEGORIES.${value}`),
  }))
);
const open = () => {
  confirmed = false;
  name.value = '';
  categories.value = [];
  template.value = 'blank';
  triedToCreate.value = false;
  dialog.value.open();
};
const create = () => {
  triedToCreate.value = true;
  if (!name.value.trim()) return;
  const flow = {
    id: null,
    name: name.value.trim(),
    categories: categories.value.length ? [...categories.value] : ['OTHER'],
    definition: startingDefinition(template.value),
  };
  confirmed = true;
  dialog.value.close();
  emit('create', flow);
};
const onClose = () => {
  if (!confirmed) emit('cancel');
};
const onTemplateKeydown = (event, index) => {
  if (!['ArrowDown', 'ArrowUp', 'ArrowLeft', 'ArrowRight'].includes(event.key))
    return;
  event.preventDefault();
  const step = ['ArrowDown', 'ArrowRight'].includes(event.key) ? 1 : -1;
  const next = (index + step + templates.length) % templates.length;
  template.value = templates[next];
  templateList.value.querySelectorAll('[role="radio"]')[next].focus();
};
defineExpose({ open });
</script>

<template>
  <Dialog
    ref="dialog"
    width="xl"
    body-scroll
    :title="$t('WHATSAPP_FLOWS.NEW.TITLE')"
    :description="$t('WHATSAPP_FLOWS.NEW.DESCRIPTION')"
    :confirm-button-label="$t('WHATSAPP_FLOWS.NEW.CONFIRM')"
    :cancel-button-label="$t('WHATSAPP_FLOWS.NEW.CANCEL')"
    @confirm="create"
    @close="onClose"
  >
    <div class="grid gap-4">
      <Input
        v-model="name"
        autofocus
        :label="$t('WHATSAPP_FLOWS.EDITOR.NAME')"
        :message="
          triedToCreate && !name.trim()
            ? $t('WHATSAPP_FLOWS.EDITOR.NAME_REQUIRED')
            : ''
        "
        :message-type="triedToCreate && !name.trim() ? 'error' : 'info'"
        data-testid="new-flow-name"
      />
      <div class="grid gap-2">
        <span class="text-label">{{
          $t('WHATSAPP_FLOWS.NEW.CATEGORIES')
        }}</span>
        <ComboBox
          v-model="categories"
          multiple
          teleport
          :options="categoryOptions"
          :aria-label="$t('WHATSAPP_FLOWS.NEW.CATEGORIES')"
          :placeholder="$t('WHATSAPP_FLOWS.CATEGORIES.OTHER')"
          data-testid="new-flow-categories"
        />
        <p class="m-0 text-xs text-n-slate-11">
          {{ $t('WHATSAPP_FLOWS.NEW.CATEGORIES_HINT') }}
        </p>
      </div>
      <div class="grid gap-2">
        <span class="text-label">{{ $t('WHATSAPP_FLOWS.NEW.TEMPLATE') }}</span>
        <div
          ref="templateList"
          class="grid gap-2"
          role="radiogroup"
          :aria-label="$t('WHATSAPP_FLOWS.NEW.TEMPLATE')"
        >
          <Button
            v-for="(id, index) in templates"
            :key="id"
            type="button"
            ghost
            slate
            no-animation
            role="radio"
            :aria-checked="template === id"
            :tabindex="template === id ? 0 : -1"
            class="w-full !justify-start !p-3 !outline-0 !border !border-solid !rounded-lg"
            :class="
              template === id
                ? '!border-n-brand bg-n-brand/10'
                : '!border-n-weak bg-n-solid-1'
            "
            :data-testid="`new-flow-template-${id}`"
            @click="template = id"
            @keydown="onTemplateKeydown($event, index)"
          >
            <span :class="templateIcons[id]" class="size-5 shrink-0" />
            <span class="flex-1 text-start">
              <span class="block text-sm font-medium">
                {{ $t(`WHATSAPP_FLOWS.START.POINTS.${id}.TITLE`) }}
              </span>
              <span class="block mt-1 text-xs leading-4 text-n-slate-11">
                {{ $t(`WHATSAPP_FLOWS.START.POINTS.${id}.DESCRIPTION`) }}
              </span>
            </span>
            <span
              class="size-4 shrink-0"
              :class="
                template === id
                  ? 'i-lucide-circle-check text-n-blue-text'
                  : 'i-lucide-circle text-n-slate-8'
              "
            />
          </Button>
        </div>
      </div>
    </div>
  </Dialog>
</template>
