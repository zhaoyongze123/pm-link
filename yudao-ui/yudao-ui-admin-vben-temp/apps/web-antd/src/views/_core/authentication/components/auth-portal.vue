<script lang="ts" setup>
import type { AuthApi } from '#/api/core/auth';

import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref, watch } from 'vue';
import { useRoute, useRouter } from 'vue-router';

import { Verification } from '@vben/common-ui';
import { isCaptchaEnable, isTenantEnable } from '@vben/hooks';
import { useAccessStore } from '@vben/stores';

import { message } from 'ant-design-vue';

import {
  checkCaptcha,
  getCaptcha,
  getTenantByWebsite,
  getTenantSimpleList,
  sendSmsCode,
  socialAuthRedirect,
} from '#/api/core/auth';
import { useAuthStore } from '#/store';

import AntigravityBackground from './antigravity-background.vue';

const props = withDefaults(
  defineProps<{
    initialMode?: 'account' | 'mobile';
  }>(),
  {
    initialMode: 'account',
  },
);

const route = useRoute();
const router = useRouter();
const authStore = useAuthStore();
const accessStore = useAccessStore();
const tenantEnable = isTenantEnable();
const captchaEnable = isCaptchaEnable();

const verifyRef = ref();
const loginMode = ref<'account' | 'mobile'>(props.initialMode);
const tenantList = ref<AuthApi.TenantResult[]>([]);
const countdown = ref(0);
const tenantLoading = ref(false);
const sendingCode = ref(false);
const loading = computed(
  () => authStore.loginLoading || sendingCode.value || tenantLoading.value,
);

const accountForm = reactive({
  password: import.meta.env.VITE_APP_DEFAULT_PASSWORD ?? '',
  remember: true,
  tenantId: '',
  username: import.meta.env.VITE_APP_DEFAULT_USERNAME ?? '',
});

const mobileForm = reactive({
  code: '',
  mobile: '',
  tenantId: '',
});

const errors = reactive({
  account: '',
  mobile: '',
});

const tilt = reactive({
  rotateX: 0,
  rotateY: 0,
});
let targetRotateX = 0;
let targetRotateY = 0;
let animationFrameId = 0;
let countdownTimer: number | null = null;

watch(
  () => props.initialMode,
  (value) => {
    loginMode.value = value;
  },
);

function setTenantId(value: string) {
  if (!value) {
    return;
  }
  const id = Number(value);
  accountForm.tenantId = value;
  mobileForm.tenantId = value;
  accessStore.setTenantId(Number.isNaN(id) ? null : id);
}

async function fetchTenantList() {
  if (!tenantEnable) {
    return;
  }
  try {
    tenantLoading.value = true;
    const websiteTenantPromise = getTenantByWebsite(window.location.hostname);
    tenantList.value = await getTenantSimpleList();

    let tenantId: null | number = null;
    const websiteTenant = await websiteTenantPromise.catch(() => null);
    if (websiteTenant?.id) {
      tenantId = websiteTenant.id;
    }
    if (!tenantId && accessStore.tenantId) {
      tenantId = accessStore.tenantId;
    }
    if (!tenantId && tenantList.value[0]?.id) {
      tenantId = tenantList.value[0].id;
    }
    if (tenantId) {
      setTenantId(String(tenantId));
    }
  } catch (error) {
    console.error('获取租户列表失败', error);
  } finally {
    tenantLoading.value = false;
  }
}

function validateAccountForm() {
  if (tenantEnable && !accountForm.tenantId) {
    errors.account = '请选择租户';
    return false;
  }
  if (!accountForm.username || !accountForm.password) {
    errors.account = '请输入账号和密码';
    return false;
  }
  errors.account = '';
  return true;
}

function validateMobileForm() {
  if (tenantEnable && !mobileForm.tenantId) {
    errors.mobile = '请选择租户';
    return false;
  }
  if (!/^1[3-9]\d{9}$/.test(mobileForm.mobile)) {
    errors.mobile = '请输入正确的手机号';
    return false;
  }
  if (!mobileForm.code) {
    errors.mobile = '请输入验证码';
    return false;
  }
  errors.mobile = '';
  return true;
}

async function submitAccountLogin(captchaVerification?: string) {
  await authStore.authLogin('username', {
    password: accountForm.password,
    username: accountForm.username,
    ...(captchaVerification ? { captchaVerification } : {}),
  });
}

async function handleAccountLogin() {
  if (!validateAccountForm()) {
    return;
  }
  if (captchaEnable) {
    verifyRef.value?.show();
    return;
  }
  try {
    await submitAccountLogin();
  } catch (error: any) {
    errors.account = error?.message || '登录失败，请稍后重试';
  }
}

async function handleVerifySuccess({
  captchaVerification,
}: {
  captchaVerification: string;
}) {
  try {
    await submitAccountLogin(captchaVerification);
  } catch (error: any) {
    errors.account = error?.message || '登录失败，请稍后重试';
  }
}

async function handleSendCode() {
  if (tenantEnable && !mobileForm.tenantId) {
    errors.mobile = '请选择租户';
    return;
  }
  if (!/^1[3-9]\d{9}$/.test(mobileForm.mobile)) {
    errors.mobile = '请输入正确的手机号';
    return;
  }
  try {
    sendingCode.value = true;
    errors.mobile = '';
    await sendSmsCode({ mobile: mobileForm.mobile, scene: 21 });
    message.success('验证码发送成功');
    countdown.value = 60;
    countdownTimer = window.setInterval(() => {
      if (countdown.value <= 1) {
        if (countdownTimer) {
          window.clearInterval(countdownTimer);
          countdownTimer = null;
        }
        countdown.value = 0;
        return;
      }
      countdown.value -= 1;
    }, 1000);
  } catch (error: any) {
    errors.mobile = error?.message || '发送验证码失败';
  } finally {
    sendingCode.value = false;
  }
}

async function handleMobileLogin() {
  if (!validateMobileForm()) {
    return;
  }
  try {
    await authStore.authLogin('mobile', {
      code: mobileForm.code,
      mobile: mobileForm.mobile,
    });
  } catch (error: any) {
    errors.mobile = error?.message || '登录失败，请检查短信验证码';
  }
}

async function handleSocialLogin(type: number) {
  try {
    const redirect = route.query?.redirect || '/';
    const redirectUri = `${location.origin}/auth/social-login?${encodeURIComponent(
      `type=${type}&redirect=${redirect}`,
    )}`;
    window.location.href = await socialAuthRedirect(type, redirectUri);
  } catch (error: any) {
    message.error(error?.message || '无法发起第三方登录');
  }
}

function goForgetPassword() {
  router.push('/auth/forget-password');
}

function syncTilt(event: MouseEvent) {
  const { innerHeight, innerWidth } = window;
  const xIndex = (event.clientX / innerWidth - 0.5) * 2;
  const yIndex = -(event.clientY / innerHeight - 0.5) * 2;
  targetRotateX = yIndex * 9;
  targetRotateY = xIndex * 9;
}

function animateTilt() {
  tilt.rotateX += (targetRotateX - tilt.rotateX) * 0.05;
  tilt.rotateY += (targetRotateY - tilt.rotateY) * 0.05;
  animationFrameId = window.requestAnimationFrame(animateTilt);
}

onMounted(async () => {
  await fetchTenantList();
  window.addEventListener('mousemove', syncTilt);
  animateTilt();
  await nextTick();
});

onBeforeUnmount(() => {
  window.cancelAnimationFrame(animationFrameId);
  window.removeEventListener('mousemove', syncTilt);
  if (countdownTimer) {
    window.clearInterval(countdownTimer);
    countdownTimer = null;
  }
});
</script>

<template>
  <div class="auth-portal">
    <AntigravityBackground />
    <div class="auth-portal__inner">
      <section
        class="auth-panel"
        :style="{
          transform: `perspective(1000px) rotateX(${tilt.rotateX.toFixed(2)}deg) rotateY(${tilt.rotateY.toFixed(2)}deg) translateZ(10px)`,
        }"
      >
        <div class="auth-panel__header">
          <div class="auth-panel__logo">W</div>
          <h1>Workflow Approval System</h1>
          <p>登入管理视界</p>
        </div>

        <div class="auth-mode-switch">
          <button
            :class="{ active: loginMode === 'account' }"
            type="button"
            @click="loginMode = 'account'"
          >
            账号密码
          </button>
          <button
            :class="{ active: loginMode === 'mobile' }"
            type="button"
            @click="loginMode = 'mobile'"
          >
            手机验证码
          </button>
        </div>

        <form
          v-if="loginMode === 'account'"
          class="auth-form"
          @submit.prevent="handleAccountLogin"
        >
          <div v-if="errors.account" class="auth-form__error">
            {{ errors.account }}
          </div>

          <label v-if="tenantEnable && tenantList.length" class="auth-field">
            <span class="auth-field__icon">T</span>
            <select
              :value="accountForm.tenantId"
              @change="setTenantId(($event.target as HTMLSelectElement).value)"
            >
              <option disabled value="">请选择租户</option>
              <option
                v-for="tenant in tenantList"
                :key="tenant.id"
                :value="String(tenant.id)"
              >
                {{ tenant.name }}
              </option>
            </select>
          </label>

          <label class="auth-field">
            <span class="auth-field__icon">U</span>
            <input
              v-model="accountForm.username"
              autocomplete="username"
              placeholder="账号"
              type="text"
            />
          </label>

          <label class="auth-field">
            <span class="auth-field__icon">L</span>
            <input
              v-model="accountForm.password"
              autocomplete="current-password"
              placeholder="密码"
              type="password"
            />
          </label>

          <div class="auth-form__actions">
            <label class="auth-checkbox">
              <input v-model="accountForm.remember" type="checkbox" />
              <span>记住账号</span>
            </label>
            <button type="button" @click="goForgetPassword">忘记密码?</button>
          </div>

          <button class="auth-submit" :disabled="loading" type="submit">
            {{ loading ? '身份验证中...' : '登 入' }}
          </button>

          <div class="auth-social">
            <span>其他登录方式</span>
            <div class="auth-social__buttons">
              <button type="button" @click="handleSocialLogin(20)">D</button>
              <button type="button" @click="handleSocialLogin(10)">G</button>
            </div>
          </div>
        </form>

        <form v-else class="auth-form" @submit.prevent="handleMobileLogin">
          <div v-if="errors.mobile" class="auth-form__error">
            {{ errors.mobile }}
          </div>

          <label v-if="tenantEnable && tenantList.length" class="auth-field">
            <span class="auth-field__icon">T</span>
            <select
              :value="mobileForm.tenantId"
              @change="setTenantId(($event.target as HTMLSelectElement).value)"
            >
              <option disabled value="">请选择租户</option>
              <option
                v-for="tenant in tenantList"
                :key="tenant.id"
                :value="String(tenant.id)"
              >
                {{ tenant.name }}
              </option>
            </select>
          </label>

          <label class="auth-field">
            <span class="auth-field__icon">M</span>
            <input
              v-model="mobileForm.mobile"
              maxlength="11"
              placeholder="手机号"
              type="text"
            />
          </label>

          <div class="auth-code-row">
            <label class="auth-field auth-field--code">
              <span class="auth-field__icon">#</span>
              <input
                v-model="mobileForm.code"
                maxlength="6"
                placeholder="验证码"
                type="text"
              />
            </label>
            <button
              class="auth-code-btn"
              :disabled="sendingCode || countdown > 0"
              type="button"
              @click="handleSendCode"
            >
              {{ countdown > 0 ? `${countdown}s` : '获取验证码' }}
            </button>
          </div>

          <button class="auth-submit" :disabled="loading" type="submit">
            {{ loading ? '验证中...' : '登 入' }}
          </button>
        </form>
      </section>

      <div class="auth-portal__footer">Powered by Vben Architecture & Ant Design Vue</div>
    </div>

    <Verification
      v-if="captchaEnable"
      ref="verifyRef"
      :captcha-type="'blockPuzzle'"
      :check-captcha-api="checkCaptcha"
      :get-captcha-api="getCaptcha"
      :img-size="{ width: '400px', height: '200px' }"
      mode="pop"
      @on-success="handleVerifySuccess"
    />
  </div>
</template>

<style scoped>
.auth-portal {
  align-items: center;
  display: flex;
  justify-content: center;
  min-height: 100vh;
  overflow: hidden;
  padding: 24px;
  position: relative;
}

.auth-portal__inner {
  max-width: 460px;
  position: relative;
  width: 100%;
  z-index: 1;
}

.auth-panel {
  padding: 20px 18px 8px;
  transition: transform 0.2s ease-out;
}

.auth-panel__header {
  margin-bottom: 36px;
  text-align: center;
}

.auth-panel__logo {
  align-items: center;
  backdrop-filter: blur(24px);
  background: rgb(17 24 39 / 0.92);
  border: 1px solid rgb(17 24 39 / 0.88);
  border-radius: 18px;
  box-shadow: 0 16px 40px rgb(15 23 42 / 0.18);
  color: #fff;
  display: inline-flex;
  font-size: 20px;
  font-weight: 700;
  height: 52px;
  justify-content: center;
  margin-bottom: 18px;
  width: 52px;
}

.auth-panel__header h1 {
  color: #111827;
  font-size: 31px;
  font-weight: 600;
  letter-spacing: -0.03em;
  margin: 0;
}

.auth-panel__header p {
  color: #6b7280;
  font-size: 14px;
  margin: 10px 0 0;
}

.auth-mode-switch {
  backdrop-filter: blur(18px);
  background: rgb(255 255 255 / 0.42);
  border: 1px solid rgb(255 255 255 / 0.6);
  border-radius: 18px;
  box-shadow: 0 4px 18px rgb(15 23 42 / 0.06);
  display: flex;
  gap: 6px;
  margin-bottom: 24px;
  padding: 6px;
}

.auth-mode-switch button {
  background: transparent;
  border: 0;
  border-radius: 14px;
  color: #6b7280;
  cursor: pointer;
  flex: 1;
  font-size: 14px;
  font-weight: 500;
  padding: 12px 0;
  transition: all 0.25s ease;
}

.auth-mode-switch button.active {
  background: #fff;
  box-shadow: 0 4px 16px rgb(15 23 42 / 0.08);
  color: #111827;
}

.auth-form {
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.auth-form__error {
  background: rgb(254 242 242 / 0.92);
  border: 1px solid rgb(254 202 202 / 0.95);
  border-radius: 14px;
  color: #dc2626;
  font-size: 13px;
  padding: 12px 14px;
}

.auth-field {
  align-items: center;
  backdrop-filter: blur(20px);
  background: rgb(255 255 255 / 0.42);
  border: 1px solid rgb(255 255 255 / 0.68);
  border-radius: 18px;
  box-shadow:
    inset 0 2px 5px rgb(15 23 42 / 0.02),
    0 2px 6px rgb(15 23 42 / 0.03);
  display: flex;
  overflow: hidden;
  padding: 0 16px;
}

.auth-field:focus-within {
  background: rgb(255 255 255 / 0.62);
  border-color: rgb(17 24 39 / 0.2);
  box-shadow:
    inset 0 2px 5px rgb(15 23 42 / 0.02),
    0 0 0 3px rgb(17 24 39 / 0.06);
}

.auth-field__icon {
  align-items: center;
  color: #9ca3af;
  display: inline-flex;
  font-size: 16px;
  height: 100%;
  justify-content: center;
  width: 24px;
}

.auth-field input,
.auth-field select {
  background: transparent;
  border: 0;
  color: #111827;
  flex: 1;
  font-size: 14px;
  outline: none;
  padding: 15px 0 15px 12px;
}

.auth-field select {
  appearance: none;
  cursor: pointer;
}

.auth-form__actions {
  align-items: center;
  display: flex;
  justify-content: space-between;
  padding: 0 4px;
}

.auth-form__actions button {
  background: transparent;
  border: 0;
  color: #6b7280;
  cursor: pointer;
  font-size: 13px;
  transition: color 0.2s ease;
}

.auth-form__actions button:hover {
  color: #111827;
}

.auth-checkbox {
  align-items: center;
  color: #6b7280;
  cursor: pointer;
  display: inline-flex;
  font-size: 13px;
  gap: 8px;
}

.auth-checkbox input {
  accent-color: #111827;
}

.auth-submit {
  background: rgb(17 24 39 / 0.94);
  border: 0;
  border-radius: 18px;
  box-shadow: 0 18px 35px rgb(15 23 42 / 0.18);
  color: #fff;
  cursor: pointer;
  font-size: 14px;
  font-weight: 600;
  padding: 16px 0;
  transition: all 0.25s ease;
}

.auth-submit:hover:not(:disabled) {
  box-shadow: 0 22px 38px rgb(15 23 42 / 0.22);
  transform: translateY(-1px);
}

.auth-submit:disabled,
.auth-code-btn:disabled {
  cursor: not-allowed;
  opacity: 0.55;
}

.auth-social {
  border-top: 1px solid rgb(229 231 235 / 0.7);
  margin-top: 10px;
  padding-top: 24px;
  text-align: center;
}

.auth-social > span {
  color: #6b7280;
  font-size: 12px;
}

.auth-social__buttons {
  display: flex;
  gap: 14px;
  justify-content: center;
  margin-top: 16px;
}

.auth-social__buttons button,
.auth-code-btn {
  backdrop-filter: blur(16px);
  background: rgb(255 255 255 / 0.58);
  border: 1px solid rgb(255 255 255 / 0.78);
  box-shadow: 0 4px 12px rgb(15 23 42 / 0.06);
  transition: all 0.25s ease;
}

.auth-social__buttons button {
  align-items: center;
  border-radius: 999px;
  color: #4b5563;
  cursor: pointer;
  display: inline-flex;
  font-size: 18px;
  height: 42px;
  justify-content: center;
  width: 42px;
}

.auth-social__buttons button:hover,
.auth-code-btn:hover:not(:disabled) {
  background: rgb(255 255 255 / 0.9);
  color: #111827;
}

.auth-code-row {
  display: flex;
  gap: 12px;
}

.auth-field--code {
  flex: 1;
}

.auth-code-btn {
  background: rgb(255 255 255 / 0.54);
  border-radius: 18px;
  color: #4b5563;
  cursor: pointer;
  font-size: 13px;
  font-weight: 600;
  min-width: 112px;
  padding: 0 18px;
}

.auth-portal__footer {
  color: #9ca3af;
  font-size: 12px;
  letter-spacing: 0.08em;
  margin-top: 28px;
  text-align: center;
}

@media (width <= 640px) {
  .auth-portal {
    padding: 18px;
  }

  .auth-panel__header h1 {
    font-size: 26px;
  }

  .auth-code-row {
    flex-direction: column;
  }

  .auth-code-btn {
    min-height: 52px;
  }
}
</style>
