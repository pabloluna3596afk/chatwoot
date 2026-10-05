<script setup>
// Where a new form starts, in the style of Meta's own screen: a name, the categories, a starting point, and the form
// in a phone next to it as it will begin.
import { computed, ref } from 'vue';

import Button from 'dashboard/components-next/button/Button.vue';
import Input from 'dashboard/components-next/input/Input.vue';
import FlowPhonePreview from './FlowPhonePreview.vue';
import {
  CATEGORIES,
  STARTING_POINTS,
  startingDefinition,
} from './flowDefinition';

const emit = defineEmits(['create', 'cancel']);

const name = ref('');
const categories = ref([]);
const starting = ref('blank');
const showError = ref(false);

const preview = computed(() => startingDefinition(starting.value));

const toggleCategory = category => {
  categories.value = categories.value.includes(category)
    ? categories.value.filter(item => item !== category)
    : [...categories.value, category];
};

const create = () => {
  if (!name.value.trim()) {
    showError.value = true;
    return;
  }
  emit('create', {
    id: null,
    name: name.value.trim(),
    categories: categories.value,
    definition: startingDefinition(starting.value),
  });
};
</script>

<template>
  <div
    class="grid gap-8 lg:grid-cols-[minmax(0,1fr)_21rem]"
    data-testid="flow-start"
  >
    <div class="flex flex-col gap-6">
      <div>
        <h2 class="text-heading-2 text-n-slate-12">
          {{ $t('WHATSAPP_FLOWS.START.TITLE') }}
        </h2>
        <p class="mt-1 text-body-main text-n-slate-11">
          {{ $t('WHATSAPP_FLOWS.START.DESCRIPTION') }}
        </p>
      </div>

      <Input
        v-model="name"
        :label="$t('WHATSAPP_FLOWS.EDITOR.NAME')"
        :placeholder="$t('WHATSAPP_FLOWS.EDITOR.NAME_PLACEHOLDER')"
        :message="
          showError && !name.trim()
            ? $t('WHATSAPP_FLOWS.EDITOR.NAME_REQUIRED')
            : ''
        "
        message-type="error"
        data-testid="flow-start-name"
      />

      <div class="grid gap-2">
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

      <div class="grid gap-2">
        <span class="text-sm font-medium text-n-slate-12">
          {{ $t('WHATSAPP_FLOWS.START.STARTING_POINT') }}
        </span>
        <div class="grid gap-2 sm:grid-cols-2">
          <button
            v-for="id in Object.keys(STARTING_POINTS)"
            :key="id"
            type="button"
            class="flex flex-col gap-0.5 p-3 text-left border rounded-xl"
            :class="
              starting === id
                ? 'border-n-brand bg-n-alpha-2'
                : 'border-n-weak hover:bg-n-alpha-1'
            "
            :data-testid="`flow-starting-${id}`"
            @click="starting = id"
          >
            <span class="text-sm font-medium text-n-slate-12">
              {{ $t(`WHATSAPP_FLOWS.START.POINTS.${id}.TITLE`) }}
            </span>
            <span class="text-xs text-n-slate-11">
              {{ $t(`WHATSAPP_FLOWS.START.POINTS.${id}.DESCRIPTION`) }}
            </span>
          </button>
        </div>
      </div>

      <div class="flex gap-2">
        <Button
          type="button"
          slate
          :label="$t('WHATSAPP_FLOWS.START.CANCEL')"
          @click="emit('cancel')"
        />
        <Button
          type="button"
          :label="$t('WHATSAPP_FLOWS.START.CREATE')"
          data-testid="flow-start-create"
          @click="create"
        />
      </div>
    </div>

    <aside class="flex flex-col items-center lg:sticky lg:top-4 lg:self-start">
      <FlowPhonePreview :key="starting" :definition="preview" />
    </aside>
  </div>
</template>
