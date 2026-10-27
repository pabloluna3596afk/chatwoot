<script setup>
import SaveStateButton from '../SaveStateButton.vue';
</script>

<template>
  <Story
    title="Components/Button/SaveStateButton"
    :layout="{ type: 'grid', width: '720px' }"
  >
    <Variant title="Clean">
      <SaveStateButton />
    </Variant>
    <Variant title="Dirty">
      <SaveStateButton dirty />
    </Variant>
    <Variant title="Saving">
      <SaveStateButton dirty loading />
    </Variant>
    <Variant title="Invalid">
      <SaveStateButton
        dirty
        invalid
        invalid-reason="Correct the form errors before saving."
      />
    </Variant>
  </Story>
</template>
