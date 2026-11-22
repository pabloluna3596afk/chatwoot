<script setup>
import Input from 'dashboard/components-next/input/Input.vue';

const props = defineProps({ modelValue: { type: Object, required: true } });
const emit = defineEmits(['update:modelValue']);

const update = (index, field, value) => {
  const library = JSON.parse(JSON.stringify(props.modelValue));
  const input = library.button_inputs[index];
  if (input.type === 'URL') input.url[field] = value;
  else input[field] = value;
  emit('update:modelValue', library);
};
</script>

<template>
  <div class="grid gap-3" data-testid="library-draft-fields">
    <p class="text-sm text-n-slate-11">
      {{ $t('WHATSAPP_TEMPLATE_MGMT.DRAFTS.LIBRARY_READ_ONLY') }}
    </p>
    <div
      class="grid gap-2 p-4 rounded-xl bg-n-alpha-2 text-sm text-n-slate-12 whitespace-pre-wrap"
      data-testid="library-preview"
    >
      <strong v-if="modelValue.preview?.header">{{
        modelValue.preview.header
      }}</strong>
      <p>{{ modelValue.preview?.body || modelValue.template_name }}</p>
      <span
        v-for="(button, index) in modelValue.preview?.buttons || []"
        :key="index"
      >
        {{ button.text }}
      </span>
    </div>
    <template v-for="(input, index) in modelValue.button_inputs" :key="index">
      <Input
        v-if="input.type === 'PHONE_NUMBER'"
        :model-value="input.phone_number"
        :max-length="20"
        :label="
          $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.PHONE', {
            text: index + 1,
          })
        "
        :data-testid="`library-phone-${index}`"
        @update:model-value="value => update(index, 'phone_number', value)"
      />
      <template v-else>
        <Input
          :model-value="input.url.base_url"
          :max-length="2000"
          :label="
            $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.URL', {
              text: index + 1,
            })
          "
          :data-testid="`library-url-${index}`"
          @update:model-value="value => update(index, 'base_url', value)"
        />
        <Input
          :model-value="input.url.url_suffix_example || ''"
          :max-length="2000"
          :label="
            $t('WHATSAPP_TEMPLATE_MGMT.PRESETS.LIBRARY.DIALOG.URL_SUFFIX')
          "
          @update:model-value="
            value => update(index, 'url_suffix_example', value)
          "
        />
      </template>
    </template>
  </div>
</template>
