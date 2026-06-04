<script lang="ts" setup>
import AuthPortal from './components/auth-portal.vue';

defineOptions({ name: 'Login' });
</script>

<template>
  <AuthPortal initial-mode="account" />
</template>
