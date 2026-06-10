<script lang="ts" setup>
import type { CSSProperties } from 'vue';
import type { MenuRecordRaw } from '@vben/types';
import type { NotificationItem } from '@vben/layouts';

import type { SystemTenantApi } from '#/api/system/tenant';
import type { SystemNotifyMessageApi } from '#/api/system/notify/message';

import { computed, onBeforeUnmount, onMounted, ref, watch } from 'vue';
import { RouterView, useRoute } from 'vue-router';

import { useAccess } from '@vben/access';
import { AuthenticationLoginExpiredModal, useVbenModal } from '@vben/common-ui';
import { isTenantEnable, useTabs, useWatermark } from '@vben/hooks';
import { AntdProfileOutlined, IconifyIcon } from '@vben/icons';
import {
  LayoutMenu,
  LockScreen,
  Notification,
  TenantDropdown,
  UserDropdown,
} from '@vben/layouts';
import { preferences, updatePreferences } from '@vben/preferences';
import { useAccessStore, useUserStore } from '@vben/stores';
import { formatDateTime } from '@vben/utils';
import { useWebSocket } from '@vueuse/core';

import { Modal, message } from 'ant-design-vue';

import {
  extractNoticeId,
  getUnreadNotifyMessageCount,
  getUnreadNotifyMessageList,
  updateAllNotifyMessageRead,
  updateNotifyMessageRead,
} from '#/api/system/notify/message';
import { getSimpleTenantList } from '#/api/system/tenant';
import { $t } from '#/locales';
import { router } from '#/router';
import { useAuthStore } from '#/store';
import { isAdminUser } from '#/utils/oa-user';
import LoginForm from '#/views/_core/authentication/login.vue';
import NotifyMessageDetail from '#/views/system/notify/my/modules/detail.vue';

defineOptions({ name: 'UnifiedOALiteLayout' });

const OA_LITE_THEME_STORAGE_KEY = 'oa-lite-theme-mode';
const OA_LITE_THEME_EVENT = 'oa-lite-theme-change';
const OA_LITE_NOTICE_PUSH_EVENT = 'oa-lite-notice-push';
const OA_LITE_SIDEBAR_WIDTH_STORAGE_KEY = 'oa-lite-unified-sidebar-width-v2';
const OA_LITE_SIDEBAR_MIN_WIDTH = 140;
const OA_LITE_SIDEBAR_MAX_WIDTH = 320;
const OA_LITE_SIDEBAR_DEFAULT_WIDTH = 140;

interface LocalTopNavItem {
  key: string;
  label: string;
  path: string;
}

const BPM_MANAGEMENT_MENU_PATHS = new Set([
  '/bpm/category',
  '/bpm/manager/form',
  '/bpm/manager/template',
  '/bpm/manager/model',
  '/bpm/manager/definition',
  '/bpm/group',
  '/bpm/process-expression',
  '/bpm/process-listener',
]);

const BPM_MANAGEMENT_MENU_ITEMS: MenuRecordRaw[] = [
  {
    name: '流程分类',
    path: '/bpm/category',
  },
  {
    name: '流程表单',
    path: '/bpm/manager/form',
  },
  {
    name: '审批模板管理',
    path: '/bpm/manager/template',
  },
  {
    name: '流程模型',
    path: '/bpm/manager/model',
  },
  {
    name: '流程定义',
    path: '/bpm/manager/definition',
  },
  {
    name: '用户组',
    path: '/bpm/group',
  },
  {
    name: '流程表达式',
    path: '/bpm/process-expression',
  },
  {
    name: '流程监听器',
    path: '/bpm/process-listener',
  },
];

const SYSTEM_MANAGEMENT_MENU_PATHS = new Set([
  '/system/user',
  '/system/role',
  '/system/dept',
  '/system/menu',
  '/system/post',
  '/system/notice',
  '/system/personal-schedule',
  '/system/meeting-room',
  '/system/meeting-booking',
  '/system/meeting-booking/schedule',
]);

const SYSTEM_MANAGEMENT_MENU_ITEMS: MenuRecordRaw[] = [
  {
    name: '用户管理',
    path: '/system/user',
  },
  {
    name: '角色管理',
    path: '/system/role',
  },
  {
    name: '部门管理',
    path: '/system/dept',
  },
  {
    name: '菜单管理',
    path: '/system/menu',
  },
  {
    name: '岗位管理',
    path: '/system/post',
  },
  {
    name: '通知公告',
    path: '/system/notice',
  },
  {
    name: '个人日程',
    path: '/system/personal-schedule',
  },
  {
    name: '会议室管理',
    path: '/system/meeting-room',
  },
  {
    name: '会议室预定',
    path: '/system/meeting-booking',
  },
  {
    name: '会议室排期',
    path: '/system/meeting-booking/schedule',
  },
];

const MEETING_CENTER_MENU_PATHS = new Set([
  '/meeting-room/booking',
  '/meeting-room/schedule',
]);

const MEETING_CENTER_MENU_ITEMS: MenuRecordRaw[] = [
  {
    name: '会议室预定',
    path: '/meeting-room/booking',
  },
  {
    name: '会议室排期',
    path: '/meeting-room/schedule',
  },
];

const SCHEDULE_CENTER_MENU_PATHS = new Set([
  '/schedule/calendar',
]);

const SCHEDULE_CENTER_MENU_ITEMS: MenuRecordRaw[] = [
  {
    name: '个人日程',
    path: '/schedule/calendar',
  },
];

function stripHtmlContent(value?: string) {
  if (!value) {
    return '';
  }
  return value
    .replace(/<style[\s\S]*?>[\s\S]*?<\/style>/gi, ' ')
    .replace(/<script[\s\S]*?>[\s\S]*?<\/script>/gi, ' ')
    .replace(/<[^>]+>/g, ' ')
    .replace(/&nbsp;/gi, ' ')
    .replace(/&amp;/gi, '&')
    .replace(/&lt;/gi, '<')
    .replace(/&gt;/gi, '>')
    .replace(/\s+/g, ' ')
    .trim();
}

function resolveNotificationPreview(
  item: Pick<
    SystemNotifyMessageApi.NotifyMessage,
    'templateCode' | 'templateContent' | 'templateParams'
  >,
) {
  const noticeId = extractNoticeId(item);
  if (!noticeId) {
    return stripHtmlContent(item.templateContent) || '点击查看详情';
  }
  const content =
    typeof item.templateParams?.content === 'string' ? item.templateParams.content : '';
  return stripHtmlContent(content || item.templateContent) || '点击查看公告详情';
}

function flattenMenus(
  menus: MenuRecordRaw[] = [],
  result: MenuRecordRaw[] = [],
) {
  menus.forEach((menu) => {
    result.push(menu);
    if (menu.children?.length) {
      flattenMenus(menu.children, result);
    }
  });
  return result;
}

const route = useRoute();
const userStore = useUserStore();
const authStore = useAuthStore();
const accessStore = useAccessStore();
const { hasAccessByCodes } = useAccess();
const { destroyWatermark, updateWatermark } = useWatermark();
const { closeOtherTabs, refreshTab } = useTabs();

const notifications = ref<NotificationItem[]>([]);
const notificationMessageMap = ref<
  Record<string, SystemNotifyMessageApi.NotifyMessage>
>({});
const unreadCount = ref(0);
const tenants = ref<SystemTenantApi.Tenant[]>([]);
const notificationTimer = ref<null | ReturnType<typeof setInterval>>(null);
const themeMode = ref<'dark' | 'light'>('light');
const settingsOpen = ref(false);
const webSocketServer = ref('');
const sidebarWidth = ref(OA_LITE_SIDEBAR_DEFAULT_WIDTH);
const isSidebarResizing = ref(false);
let removeSidebarResizeListeners: (() => void) | null = null;
const {
  data: webSocketData,
  close: closeWebSocket,
  open: openWebSocket,
} = useWebSocket(webSocketServer, {
  autoReconnect: true,
  heartbeat: true,
  immediate: false,
});

const showNotificationDot = computed(() => unreadCount.value > 0);
const avatar = computed(
  () => userStore.userInfo?.avatar ?? preferences.app.defaultAvatar,
);
const tenantEnable = computed(
  () => hasAccessByCodes(['system:tenant:visit']) && isTenantEnable(),
);

const userMenus = computed(() => [
  {
    handler: () => {
      router.push({ name: 'Profile' });
    },
    icon: AntdProfileOutlined,
    text: $t('ui.widgets.profile'),
  },
]);

const [NotifyMessageDetailModal, notifyMessageDetailModalApi] = useVbenModal({
  connectedComponent: NotifyMessageDetail,
  destroyOnClose: true,
});

const themeToggleLabel = computed(() =>
  themeMode.value === 'dark' ? '切换浅色模式' : '切换暗色模式',
);

const fixedTopNavItems = computed<LocalTopNavItem[]>(() => [
  {
    key: 'oa-create',
    label: '发起审批',
    path: '/oa-lite',
  },
  {
    key: 'oa-center',
    label: '审批中心',
    path: '/oa-lite/center',
  },
]);

const accessRootMenus = computed<MenuRecordRaw[]>(() => accessStore.accessMenus);
const accessFlatMenus = computed<MenuRecordRaw[]>(() =>
  flattenMenus(accessRootMenus.value, []),
);
const isAdminWorkbenchUser = computed(() =>
  isAdminUser(userStore.userRoles || []),
);
const bpmRootMenu = computed(
  () =>
    accessFlatMenus.value.find(
      (menu) =>
        menu.path === '/bpm' ||
        menu.path?.startsWith('/bpm/') ||
        menu.name === '流程管理',
    ) || null,
);
const systemRootMenu = computed(
  () =>
    accessFlatMenus.value.find(
      (menu) =>
        menu.path === '/system' ||
        menu.path?.startsWith('/system/') ||
        menu.name === '系统管理',
    ) || null,
);
const meetingCenterRootMenu = computed(
  () =>
    accessFlatMenus.value.find(
      (menu) =>
        menu.path === '/meeting-room' ||
        menu.path?.startsWith('/meeting-room/') ||
        menu.name === '会议室',
    ) || null,
);
const scheduleCenterRootMenu = computed(
  () =>
    accessFlatMenus.value.find(
      (menu) =>
        menu.path === '/schedule' ||
        menu.path?.startsWith('/schedule/') ||
        menu.name === '日程',
    ) || null,
);
const managementTopNavItems = computed<LocalTopNavItem[]>(() =>
  isAdminWorkbenchUser.value
    ? [
        (bpmRootMenu.value || isAdminWorkbenchUser.value)
          ? {
              key: '/bpm',
              label: '流程管理',
              path: '/bpm/manager/model',
            }
          : null,
        (systemRootMenu.value || isAdminWorkbenchUser.value)
          ? {
              key: '/system',
              label: '系统管理',
              path: '/system/user',
            }
          : null,
      ].filter((item): item is LocalTopNavItem => Boolean(item))
    : [
        {
          key: '/schedule',
          label: '日程',
          path: '/schedule',
        },
        {
          key: '/meeting-room',
          label: '会议室',
          path: '/meeting-room',
        },
      ],
);
const currentActivePath = computed(() =>
  String(route.meta.activePath || route.path),
);
const isOARequestRoute = computed(() => route.path.startsWith('/bpm/oa/'));
const isWorkbenchCreateRoute = computed(
  () => route.path === '/oa-lite' || isOARequestRoute.value,
);
const isWorkbenchCenterRoute = computed(
  () =>
    route.path === '/oa-lite/center' ||
    route.path.startsWith('/oa-lite/notifications'),
);
const isWorkbenchRoute = computed(
  () => isWorkbenchCreateRoute.value || isWorkbenchCenterRoute.value,
);

const currentMatchedMenu = computed(() => {
  const matched =
    accessStore.getMenuByPath(currentActivePath.value) ||
    accessStore.getMenuByPath(route.path);
  if (matched) {
    return matched;
  }
  if (route.path.startsWith('/system/')) {
    return accessStore.getMenuByPath('/system/user');
  }
  if (route.path.startsWith('/meeting-room/')) {
    return (
      accessStore.getMenuByPath('/meeting-room/booking') ||
      accessStore.getMenuByPath('/meeting-room/schedule') ||
      meetingCenterRootMenu.value
    );
  }
  if (route.path.startsWith('/schedule/')) {
    return (
      accessStore.getMenuByPath('/schedule/calendar') ||
      scheduleCenterRootMenu.value
    );
  }
  if (route.path.startsWith('/bpm/')) {
    return (
      accessStore.getMenuByPath('/bpm/manager/model') ||
      accessStore.getMenuByPath('/bpm/manager/form') ||
      accessStore.getMenuByPath('/bpm/category') ||
      accessStore.getMenuByPath('/bpm/group') ||
      accessStore.getMenuByPath('/bpm/process-expression') ||
      accessStore.getMenuByPath('/bpm/process-listener') ||
      bpmRootMenu.value
    );
  }
  return null;
});

const currentRootMenuPath = computed(() => {
  if (isOARequestRoute.value) {
    return '';
  }
  if (route.path === '/bpm' || route.path.startsWith('/bpm/')) {
    return '/bpm';
  }
  if (route.path === '/system' || route.path.startsWith('/system/')) {
    return '/system';
  }
  if (route.path === '/meeting-room' || route.path.startsWith('/meeting-room/')) {
    return '/meeting-room';
  }
  if (route.path === '/schedule' || route.path.startsWith('/schedule/')) {
    return '/schedule';
  }
  const matchedMenu = currentMatchedMenu.value;
  if (!matchedMenu) {
    return '';
  }
  return matchedMenu.parents?.[0] || matchedMenu.path || '';
});

const currentRootMenu = computed(
  () => {
    if (currentRootMenuPath.value === '/bpm') {
      return bpmRootMenu.value;
    }
    if (currentRootMenuPath.value === '/system') {
      return systemRootMenu.value;
    }
    if (currentRootMenuPath.value === '/meeting-room') {
      return meetingCenterRootMenu.value;
    }
    if (currentRootMenuPath.value === '/schedule') {
      return scheduleCenterRootMenu.value;
    }
    return (
      accessRootMenus.value.find(
        (menu) => menu.path === currentRootMenuPath.value,
      ) || null
    );
  },
);

function filterSidebarMenusByRoot(
  rootMenuPath: string,
  menus: MenuRecordRaw[],
): MenuRecordRaw[] {
  if (rootMenuPath === '/bpm') {
    const flattenedMenus = flattenMenus(menus, []);
    const dynamicBpmMenus = flattenedMenus.filter((menu) =>
      BPM_MANAGEMENT_MENU_PATHS.has(menu.path || ''),
    );
    if (dynamicBpmMenus.length > 0) {
      return BPM_MANAGEMENT_MENU_ITEMS.map((item) => {
        return dynamicBpmMenus.find((menu) => menu.path === item.path) || item;
      });
    }
    return BPM_MANAGEMENT_MENU_ITEMS;
  }
  if (rootMenuPath === '/system') {
    const flattenedMenus = flattenMenus(menus, []);
    const dynamicSystemMenus = flattenedMenus.filter((menu) =>
      SYSTEM_MANAGEMENT_MENU_PATHS.has(menu.path || ''),
    );
    if (dynamicSystemMenus.length > 0) {
      const baseMenus = SYSTEM_MANAGEMENT_MENU_ITEMS.map((item) => {
        return dynamicSystemMenus.find((menu) => menu.path === item.path) || item;
      });
      const extraMenus = dynamicSystemMenus.filter(
        (menu) =>
          menu.path &&
          !SYSTEM_MANAGEMENT_MENU_ITEMS.some((item) => item.path === menu.path),
      );
      return [...baseMenus, ...extraMenus];
    }
    return SYSTEM_MANAGEMENT_MENU_ITEMS;
  }
  if (rootMenuPath === '/meeting-room') {
    const flattenedMenus = flattenMenus(menus, []);
    const dynamicMeetingMenus = flattenedMenus.filter((menu) =>
      MEETING_CENTER_MENU_PATHS.has(menu.path || ''),
    );
    if (dynamicMeetingMenus.length > 0) {
      return MEETING_CENTER_MENU_ITEMS.map((item) => {
        return dynamicMeetingMenus.find((menu) => menu.path === item.path) || item;
      });
    }
    return MEETING_CENTER_MENU_ITEMS;
  }
  if (rootMenuPath === '/schedule') {
    const flattenedMenus = flattenMenus(menus, []);
    const dynamicScheduleMenus = flattenedMenus.filter((menu) =>
      SCHEDULE_CENTER_MENU_PATHS.has(menu.path || ''),
    );
    if (dynamicScheduleMenus.length > 0) {
      return SCHEDULE_CENTER_MENU_ITEMS.map((item) => {
        return dynamicScheduleMenus.find((menu) => menu.path === item.path) || item;
      });
    }
    return SCHEDULE_CENTER_MENU_ITEMS;
  }
  return menus;
}

const sidebarMenus = computed<MenuRecordRaw[]>(
  () =>
    filterSidebarMenusByRoot(
      currentRootMenuPath.value,
      currentRootMenu.value?.children || [],
    ),
);

const sidebarOpeneds = computed(() => {
  if (currentRootMenuPath.value === '/bpm') {
    return [];
  }
  const matchedMenu = currentMatchedMenu.value;
  if (!matchedMenu?.parents?.length) {
    return [];
  }
  return matchedMenu.parents.filter((path) => path !== currentRootMenuPath.value);
});

const sidebarMenuKey = computed(
  () => `${currentRootMenuPath.value}:${currentActivePath.value}`,
);

const showSidebar = computed(
  () => !isWorkbenchRoute.value && sidebarMenus.value.length > 0,
);
const sidebarStyle = computed<CSSProperties>(() => ({
  width: `${sidebarWidth.value}px`,
}) as CSSProperties);

const activeTopNavKey = computed(() => {
  if (isWorkbenchCreateRoute.value) {
    return 'oa-create';
  }
  if (isWorkbenchCenterRoute.value) {
    return 'oa-center';
  }
  if (route.path === '/system' || route.path.startsWith('/system/')) {
    return '/system';
  }
  if (route.path === '/meeting-room' || route.path.startsWith('/meeting-room/')) {
    return '/meeting-room';
  }
  if (route.path === '/schedule' || route.path.startsWith('/schedule/')) {
    return '/schedule';
  }
  if (route.path === '/bpm' || route.path.startsWith('/bpm/')) {
    return '/bpm';
  }
  return currentRootMenuPath.value;
});
const isSystemRootActive = computed(
  () => currentRootMenuPath.value === systemRootMenu.value?.path,
);

const contentStyle = computed<CSSProperties>(() => ({
  '--vben-content-height': showSidebar.value
    ? 'calc(100vh - 132px)'
    : 'calc(100vh - 132px)',
  '--vben-content-width': showSidebar.value
    ? 'calc(100vw - 420px)'
    : 'calc(100vw - 80px)',
}) as CSSProperties);

function handleTopNavSelect(path: string) {
  if (path === route.path) {
    return;
  }
  router.push(path);
}

function buildWebSocketServer(refreshToken: string) {
  return `${`${import.meta.env.VITE_BASE_URL}/infra/ws`.replace(
    'http',
    'ws',
  )}?token=${encodeURIComponent(refreshToken)}`;
}

function connectNoticeWebSocket() {
  const refreshToken = accessStore.refreshToken as string;
  if (!refreshToken) {
    return;
  }
  const nextServer = buildWebSocketServer(refreshToken);
  if (webSocketServer.value !== nextServer) {
    closeWebSocket();
    webSocketServer.value = nextServer;
  }
  openWebSocket();
}

function parseNoticePushMessage(rawMessage: string) {
  if (rawMessage === 'pong') {
    return null;
  }
  const envelope = JSON.parse(rawMessage);
  if (envelope.type !== 'notice-push' || !envelope.content) {
    return null;
  }
  return JSON.parse(envelope.content) as {
    content: string;
    createTime?: string;
    id: number;
    title: string;
    type?: number;
  };
}

async function handleNoticePushBroadcast(rawMessage: string) {
  const notice = parseNoticePushMessage(rawMessage);
  if (!notice) {
    return;
  }
  await Promise.all([
    handleNotificationGetUnreadCount(),
    handleNotificationGetList(),
  ]);
  message.info(`收到公告：${notice.title}`);
  if (typeof window !== 'undefined') {
    window.dispatchEvent(
      new CustomEvent(OA_LITE_NOTICE_PUSH_EVENT, {
        detail: notice,
      }),
    );
  }
}

function handleSidebarSelect(path: string) {
  if (path === route.path) {
    return;
  }
  router.push(path);
}

function clampSidebarWidth(nextWidth: number) {
  return Math.min(
    OA_LITE_SIDEBAR_MAX_WIDTH,
    Math.max(OA_LITE_SIDEBAR_MIN_WIDTH, nextWidth),
  );
}

function persistSidebarWidth() {
  if (typeof window === 'undefined') {
    return;
  }
  window.localStorage.setItem(
    OA_LITE_SIDEBAR_WIDTH_STORAGE_KEY,
    String(sidebarWidth.value),
  );
}

function stopSidebarResize() {
  isSidebarResizing.value = false;
  removeSidebarResizeListeners?.();
  removeSidebarResizeListeners = null;
}

function handleSidebarResizeStart(event: MouseEvent) {
  if (typeof window === 'undefined' || window.innerWidth <= 768) {
    return;
  }
  event.preventDefault();
  const startX = event.clientX;
  const startWidth = sidebarWidth.value;
  isSidebarResizing.value = true;

  const handleMouseMove = (moveEvent: MouseEvent) => {
    const deltaX = moveEvent.clientX - startX;
    sidebarWidth.value = clampSidebarWidth(startWidth + deltaX);
  };

  const handleMouseUp = () => {
    persistSidebarWidth();
    stopSidebarResize();
  };

  window.addEventListener('mousemove', handleMouseMove);
  window.addEventListener('mouseup', handleMouseUp, { once: true });

  removeSidebarResizeListeners = () => {
    window.removeEventListener('mousemove', handleMouseMove);
    window.removeEventListener('mouseup', handleMouseUp);
  };
}

function handleRefresh() {
  router.go(0);
}

function handleThemeToggle() {
  themeMode.value = themeMode.value === 'dark' ? 'light' : 'dark';
  if (typeof window !== 'undefined') {
    window.localStorage.setItem(OA_LITE_THEME_STORAGE_KEY, themeMode.value);
    window.dispatchEvent(
      new CustomEvent(OA_LITE_THEME_EVENT, {
        detail: themeMode.value,
      }),
    );
  }
  updatePreferences({
    theme: {
      mode: themeMode.value,
      semiDarkHeader: false,
      semiDarkSidebar: false,
      semiDarkSidebarSub: false,
    },
  });
}

function handleSystemSettings() {
  settingsOpen.value = true;
}

async function handleLogout() {
  await authStore.logout(false);
}

async function handleNotificationGetUnreadCount() {
  unreadCount.value = await getUnreadNotifyMessageCount();
}

async function handleNotificationGetList() {
  const list = await getUnreadNotifyMessageList();
  notificationMessageMap.value = Object.fromEntries(
    list.map((item) => [String(item.id), item]),
  );
  notifications.value = list.map((item) => ({
    avatar: preferences.app.defaultAvatar,
    date: formatDateTime(item.createTime) as string,
    id: item.id,
    isRead: false,
    message: resolveNotificationPreview(item),
    title: item.templateNickname,
  }));
}

function handleNotificationViewAll() {
  router.push('/oa-lite/notifications');
}

async function handleNotificationMakeAll() {
  await updateAllNotifyMessageRead();
  unreadCount.value = 0;
  notifications.value = [];
}

async function handleNotificationClear() {
  await handleNotificationMakeAll();
}

async function handleNotificationRead(item: NotificationItem) {
  if (!item.id) {
    return;
  }
  await updateNotifyMessageRead([item.id]);
  await handleNotificationGetUnreadCount();
  notifications.value = notifications.value.filter((n) => n.id !== item.id);
}

async function handleNotificationItemClick(item: NotificationItem) {
  const messageItem = notificationMessageMap.value[String(item.id)];
  if (!messageItem) {
    return;
  }
  if (!messageItem.readStatus) {
    await updateNotifyMessageRead([messageItem.id]);
    await handleNotificationGetUnreadCount();
    await handleNotificationGetList();
  }
  notifyMessageDetailModalApi.setData({
    ...messageItem,
    readStatus: true,
    readTime: messageItem.readTime || new Date(),
  }).open();
}

function handleNotificationOpen(open: boolean) {
  if (!open) {
    return;
  }
  handleNotificationGetList();
  handleNotificationGetUnreadCount();
}

async function handleGetTenantList() {
  if (tenantEnable.value) {
    tenants.value = await getSimpleTenantList();
  }
}

async function handleTenantChange(tenant: SystemTenantApi.Tenant) {
  if (!tenant?.id) {
    message.error('切换租户失败');
    return;
  }
  accessStore.setVisitTenantId(tenant.id as number);
  await closeOtherTabs();
  await refreshTab();
  message.success(`切换当前租户为: ${tenant.name}`);
}

watch(
  () => ({
    enable: preferences.app.watermark,
    content: preferences.app.watermarkContent,
  }),
  async ({ enable, content }) => {
    if (enable) {
      await updateWatermark({
        content:
          content ||
          `${userStore.userInfo?.id} - ${userStore.userInfo?.nickname}`,
      });
    } else {
      destroyWatermark();
    }
  },
  {
    immediate: true,
  },
);

watch(
  tenantEnable,
  (enable) => {
    if (enable) {
      handleGetTenantList();
    }
  },
  {
    immediate: true,
  },
);

onMounted(() => {
  if (typeof window !== 'undefined') {
    themeMode.value =
      window.localStorage.getItem(OA_LITE_THEME_STORAGE_KEY) === 'dark'
        ? 'dark'
        : 'light';
    const savedSidebarWidth = Number.parseInt(
      window.localStorage.getItem(OA_LITE_SIDEBAR_WIDTH_STORAGE_KEY) || '',
      10,
    );
    if (!Number.isNaN(savedSidebarWidth)) {
      sidebarWidth.value = clampSidebarWidth(savedSidebarWidth);
    }
  }
  connectNoticeWebSocket();
  handleNotificationGetUnreadCount();
  notificationTimer.value = setInterval(() => {
    if (userStore.userInfo) {
      handleNotificationGetUnreadCount();
    }
  }, 1000 * 60 * 2);
});

onBeforeUnmount(() => {
  closeWebSocket();
  stopSidebarResize();
  if (notificationTimer.value) {
    clearInterval(notificationTimer.value);
    notificationTimer.value = null;
  }
});

watch(
  () => webSocketData.value,
  async (rawMessage) => {
    if (!rawMessage) {
      return;
    }
    try {
      await handleNoticePushBroadcast(rawMessage);
    } catch (error) {
      console.error('处理通知公告实时消息失败', error);
    }
  },
);

watch(
  settingsOpen,
  (open) => {
    if (!open) {
      return;
    }
  },
  { immediate: false },
);
</script>

<template>
  <div class="oa-lite-unified-layout">
    <div class="oa-lite-unified-bg"></div>

    <header class="oa-lite-unified-topbar">
      <button class="oa-lite-unified-brand" @click="handleTopNavSelect('/oa-lite')">
        <span class="oa-lite-unified-brand-icon">
          <IconifyIcon icon="carbon:task-asset-view" />
        </span>
        <span class="oa-lite-unified-brand-copy">
          <span class="oa-lite-unified-brand-title">OA 审批</span>
        </span>
      </button>

      <nav class="oa-lite-unified-topnav">
        <button
          v-for="item in fixedTopNavItems"
          :key="item.key"
          class="oa-lite-unified-topnav-item"
          :class="{ active: activeTopNavKey === item.key }"
          @click="handleTopNavSelect(item.path)"
        >
          {{ item.label }}
        </button>
        <button
          v-for="item in managementTopNavItems"
          :key="item.key"
          class="oa-lite-unified-topnav-item oa-lite-unified-topnav-menu"
          :class="{ active: activeTopNavKey === item.key }"
          @click="handleTopNavSelect(item.path)"
        >
          {{ item.label }}
        </button>
      </nav>

      <div class="oa-lite-unified-actions">
        <div
          v-if="tenantEnable"
          class="oa-lite-unified-action-card oa-lite-unified-tenant"
        >
          <TenantDropdown
            :tenant-list="tenants"
            :visit-tenant-id="accessStore.visitTenantId"
            @success="handleTenantChange"
          />
        </div>

        <div class="oa-lite-unified-action-card">
          <button
            class="oa-lite-unified-icon-button"
            aria-label="刷新页面"
            @click="handleRefresh"
          >
            <IconifyIcon icon="solar:refresh-outline" />
          </button>
          <button
            class="oa-lite-unified-icon-button"
            :aria-label="themeToggleLabel"
            @click="handleThemeToggle"
          >
            <IconifyIcon
              :icon="
                themeMode === 'dark'
                  ? 'solar:sun-2-outline'
                  : 'solar:moon-stars-outline'
              "
            />
          </button>
          <NotifyMessageDetailModal />
          <Notification
            :dot="showNotificationDot"
            :notifications="notifications"
            @clear="handleNotificationClear"
            @item-click="handleNotificationItemClick"
            @make-all="handleNotificationMakeAll"
            @open="handleNotificationOpen"
            @read="handleNotificationRead"
            @view-all="handleNotificationViewAll"
          />
          <button
            class="oa-lite-unified-icon-button"
            :class="{ active: isSystemRootActive || settingsOpen }"
            aria-label="打开设置"
            @click="handleSystemSettings"
          >
            <IconifyIcon icon="solar:settings-outline" />
          </button>
          <UserDropdown
            :avatar="avatar"
            :description="userStore.userInfo?.email"
            :menus="userMenus"
            :tag-text="userStore.userInfo?.username"
            :text="userStore.userInfo?.nickname"
            @logout="handleLogout"
          />
        </div>
      </div>
    </header>

    <main
      class="oa-lite-unified-main"
      :class="{
        'is-workbench': isWorkbenchRoute,
        'is-workbench-center': isWorkbenchCenterRoute,
      }"
    >
      <aside
        v-if="showSidebar"
        class="oa-lite-unified-sidebar"
        :style="sidebarStyle"
      >
        <div class="oa-lite-unified-sidebar-card">
          <div
            v-if="currentRootMenuPath !== '/bpm' && currentRootMenuPath !== '/system'"
            class="oa-lite-unified-sidebar-title"
          >
            {{ currentRootMenu?.name }}
          </div>
          <LayoutMenu
            :key="sidebarMenuKey"
            class="oa-lite-unified-menu"
            :default-active="currentActivePath"
            :default-openeds="sidebarOpeneds"
            :menus="sidebarMenus"
            mode="vertical"
            scroll-to-active
            theme="light"
            @select="handleSidebarSelect"
          />
        </div>
      </aside>
      <button
        v-if="showSidebar"
        class="oa-lite-unified-resizer"
        :class="{ active: isSidebarResizing }"
        aria-label="调整侧边栏宽度"
        @mousedown="handleSidebarResizeStart"
      ></button>

      <section
        class="oa-lite-unified-content"
        :class="{ 'is-workbench': isWorkbenchRoute }"
        :style="contentStyle"
      >
        <div
          class="oa-lite-unified-content-shell"
          :class="{ 'is-workbench': isWorkbenchRoute }"
        >
          <RouterView v-slot="{ Component }">
            <component :is="Component" v-if="Component" />
          </RouterView>
        </div>
      </section>
    </main>

    <AuthenticationLoginExpiredModal
      v-model:open="accessStore.loginExpired"
      :avatar="avatar"
    >
      <LoginForm />
    </AuthenticationLoginExpiredModal>

    <Modal
      v-model:open="settingsOpen"
      :footer="null"
      :width="1080"
      centered
      title="工作台设置"
      wrap-class-name="oa-lite-settings-modal"
    >
      <div class="oa-lite-settings-sheet">
        <aside class="oa-lite-settings-sidebar">
          <div class="oa-lite-settings-sidebar-head">
            <p class="oa-lite-settings-eyebrow">Workspace Console</p>
            <h3>工作台设置</h3>
            <p>这里只保留界面控制项，模块导航已经回到顶部主导航。</p>
          </div>
        </aside>

        <section class="oa-lite-settings-content">
          <header class="oa-lite-settings-content-head">
            <div>
              <div class="oa-lite-settings-content-title">界面控制台</div>
              <p>集中处理主题和当前界面刷新，主导航负责系统管理与流程管理切换。</p>
            </div>
          </header>

          <section class="oa-lite-settings-section">
            <div class="oa-lite-settings-section-head">
              <div>
                <h4>主题模式</h4>
                <p>统一锁定这套工作台的明暗风格，不再分散到页面里单独处理。</p>
              </div>
            </div>
            <div class="oa-lite-settings-split-choice">
              <button
                class="oa-lite-settings-choice"
                :class="{ active: themeMode === 'light' }"
                type="button"
                @click="themeMode !== 'light' && handleThemeToggle()"
              >
                <span class="oa-lite-settings-choice-title">浅色</span>
                <span class="oa-lite-settings-choice-desc">
                  适合白天办公和分屏使用，保持 oa-lite 的轻量工作台观感。
                </span>
              </button>
              <button
                class="oa-lite-settings-choice"
                :class="{ active: themeMode === 'dark' }"
                type="button"
                @click="themeMode !== 'dark' && handleThemeToggle()"
              >
                <span class="oa-lite-settings-choice-title">暗色</span>
                <span class="oa-lite-settings-choice-desc">
                  适合夜间场景，延续统一的深色信息层级和低干扰对比。
                </span>
              </button>
            </div>
          </section>

          <section class="oa-lite-settings-section">
            <div class="oa-lite-settings-section-head">
              <div>
                <h4>工作区操作</h4>
                <p>当前页面的快捷控制集中在这里，避免把操作按钮散落到多个区域。</p>
              </div>
            </div>
            <div class="oa-lite-settings-list">
              <button class="oa-lite-settings-row" type="button" @click="handleRefresh">
                <span class="oa-lite-settings-row-main">
                  <IconifyIcon icon="solar:refresh-outline" />
                  <span class="oa-lite-settings-row-copy">
                    <span class="oa-lite-settings-row-title">刷新当前界面</span>
                    <span class="oa-lite-settings-row-desc">
                      重新拉取当前路由数据和界面状态，不改变顶部导航结构。
                    </span>
                  </span>
                </span>
                <span class="oa-lite-settings-row-meta">立即执行</span>
              </button>
            </div>
          </section>
        </section>
      </div>
    </Modal>

    <LockScreen
      v-if="accessStore.isLockScreen"
      :avatar="avatar"
      @to-login="handleLogout"
    />
  </div>
</template>

<style scoped>
.oa-lite-unified-layout {
  position: relative;
  min-height: 100vh;
  overflow-x: hidden;
  background: var(--oa-shell-bg);
  color: var(--oa-ink);
}

.oa-lite-unified-bg {
  position: fixed;
  inset: 0;
  pointer-events: none;
  background:
    linear-gradient(
      180deg,
      color-mix(in srgb, var(--oa-shell-surface) 72%, transparent) 0%,
      color-mix(in srgb, var(--oa-shell-surface-subtle) 88%, transparent) 88px,
      transparent 240px
    );
  opacity: 1;
}

:global(body.oa-lite-theme-dark) .oa-lite-unified-bg {
  background:
    linear-gradient(
      180deg,
      rgb(10 18 28 / 72%) 0%,
      rgb(10 18 28 / 28%) 88px,
      transparent 240px
    );
}

.oa-lite-unified-topbar {
  position: sticky;
  top: 0;
  z-index: 40;
  display: grid;
  grid-template-columns: 220px minmax(0, 1fr) auto;
  align-items: center;
  gap: 24px;
  padding: 14px 24px 12px;
  background: color-mix(in srgb, var(--oa-overlay-bg) 100%, transparent);
  border-bottom: 1px solid var(--oa-shell-border);
  box-shadow: 0 1px 0 rgb(15 23 42 / 2%);
}

:global(body.oa-lite-theme-dark) .oa-lite-unified-topbar {
  background: rgb(10 18 28 / 96%);
  box-shadow: none;
}

.oa-lite-unified-brand {
  display: flex;
  align-items: center;
  gap: 14px;
  border: 0;
  background: transparent;
  text-align: left;
}

.oa-lite-unified-brand-icon {
  display: flex;
  size: 36px;
  align-items: center;
  justify-content: center;
  border: 1px solid var(--oa-shell-border);
  border-radius: 0;
  background: transparent;
  color: var(--oa-accent);
  font-size: 18px;
}

.oa-lite-unified-brand-copy {
  display: flex;
  flex-direction: column;
  gap: 2px;
}

.oa-lite-unified-brand-title {
  color: var(--oa-ink);
  font-size: 16px;
  font-weight: 600;
}

.oa-lite-unified-topnav {
  display: flex;
  min-width: 0;
  align-items: center;
  gap: 0;
  overflow-x: auto;
  padding: 0;
  border-bottom: 0;
  border-radius: 0;
  background: transparent;
}

.oa-lite-unified-topnav::-webkit-scrollbar {
  display: none;
}

.oa-lite-unified-topnav-item {
  flex: none;
  height: 42px;
  padding: 0 16px;
  border: 0;
  border-bottom: 2px solid transparent;
  border-radius: 0;
  background: transparent;
  color: var(--oa-ink-soft);
  font-size: 14px;
  font-weight: 500;
  transition:
    background-color 0.2s ease,
    color 0.2s ease,
    border-color 0.2s ease;
}

.oa-lite-unified-topnav-item:hover,
.oa-lite-unified-topnav-item.active {
  background: transparent;
  color: var(--oa-ink);
}

.oa-lite-unified-topnav-item.active {
  border-bottom-color: var(--oa-accent);
  color: var(--oa-accent);
  background: transparent;
}

.oa-lite-unified-actions {
  display: flex;
  align-items: center;
  gap: 12px;
}

.oa-lite-unified-action-card {
  display: flex;
  align-items: center;
  gap: 2px;
  padding: 0;
  border-radius: 0;
  border: 0;
  background: transparent;
}

.oa-lite-unified-icon-button {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  width: 36px;
  height: 36px;
  border: 0;
  border-radius: 0;
  background: transparent;
  color: var(--oa-ink-soft);
  transition:
    background-color 0.2s ease,
    color 0.2s ease;
}

.oa-lite-unified-icon-button:hover,
.oa-lite-unified-icon-button.active {
  background: transparent;
  color: var(--oa-accent);
}

.oa-lite-unified-tenant {
  padding: 0 6px;
}

.oa-lite-unified-main {
  display: flex;
  gap: 16px;
  padding: 14px 24px 20px;
}

.oa-lite-unified-main.is-workbench-center {
  padding-right: 0;
  padding-left: 0;
}

.oa-lite-unified-sidebar {
  flex: none;
}

.oa-lite-unified-resizer {
  position: relative;
  flex: none;
  width: 14px;
  margin: 0 -5px;
  border: 0;
  background: transparent;
  cursor: col-resize;
  touch-action: none;
  user-select: none;

  &::before {
    content: '';
    position: absolute;
    inset: 0;
    margin: auto;
    width: 1px;
    height: 100%;
    background: color-mix(in srgb, var(--oa-shell-border) 78%, transparent);
    transition:
      background-color 0.18s ease,
      transform 0.18s ease;
  }

  &::after {
    content: '';
    position: absolute;
    top: 50%;
    left: 50%;
    width: 4px;
    height: 36px;
    border-radius: 999px;
    background: color-mix(in srgb, var(--oa-accent) 22%, transparent);
    transform: translate(-50%, -50%);
    opacity: 0;
    transition: opacity 0.18s ease;
  }

  &:hover::before,
  &.active::before {
    background: color-mix(in srgb, var(--oa-accent) 48%, var(--oa-shell-border));
    transform: scaleX(1.2);
  }

  &:hover::after,
  &.active::after {
    opacity: 1;
  }
}

.oa-lite-unified-sidebar-card {
  height: calc(100vh - 132px);
  padding: 10px 0 0;
  border-right: 1px solid var(--oa-shell-border);
  border-radius: 0;
  background: transparent;
  overflow: hidden auto;
}

.oa-lite-unified-sidebar-title {
  padding: 6px 0 14px;
  color: var(--oa-ink);
  font-size: 14px;
  font-weight: 600;
}

.oa-lite-unified-content {
  min-width: 0;
  flex: 1;
  min-height: calc(100vh - 132px);
}

.oa-lite-unified-content-shell {
  width: 100%;
  min-width: 0;
  max-width: 100%;
  min-height: 100%;
  overflow: visible;
  border-left: 1px solid var(--oa-shell-border);
  border-radius: 0;
  background: transparent;
  box-shadow: none;
}

.oa-lite-unified-content-shell.is-workbench {
  border: 0;
  border-radius: 0;
  background: transparent;
  box-shadow: none;
}

.oa-lite-unified-menu {
  height: calc(100% - 42px);
  overflow: auto;
}

.oa-lite-unified-sidebar :deep(.vben-menu) {
  padding: 0;
  background: transparent;
}

.oa-lite-unified-sidebar :deep(.vben-menu-item),
.oa-lite-unified-sidebar :deep(.vben-sub-menu-content) {
  border-radius: 0;
}

.oa-lite-unified-sidebar :deep(.vben-menu-item a),
.oa-lite-unified-sidebar :deep(.vben-sub-menu-content) {
  color: var(--oa-ink-soft);
  margin: 0;
}

.oa-lite-unified-sidebar :deep(.vben-menu-item.is-active a),
.oa-lite-unified-sidebar :deep(.vben-sub-menu-content.is-active) {
  background: color-mix(in srgb, var(--oa-accent-soft) 40%, transparent);
  color: var(--oa-accent);
  box-shadow: inset 2px 0 0 var(--oa-accent);
}

.oa-lite-unified-sidebar :deep(.vben-menu-item a:hover),
.oa-lite-unified-sidebar :deep(.vben-sub-menu-content:hover) {
  background: color-mix(in srgb, var(--oa-shell-surface-muted) 55%, transparent);
}

.oa-lite-unified-content-shell :deep(.bg-card),
.oa-lite-unified-content-shell :deep(.ant-card),
.oa-lite-unified-content-shell :deep(.vxe-grid),
.oa-lite-unified-content-shell :deep(.ant-modal-content) {
  border-radius: 0;
  box-shadow: none;
}

.oa-lite-unified-content-shell :deep(.border-border),
.oa-lite-unified-content-shell :deep(.ant-card),
.oa-lite-unified-content-shell :deep(.vxe-grid) {
  border-color: var(--oa-shell-border);
}

.oa-lite-unified-content-shell :deep(.vxe-grid),
.oa-lite-unified-content-shell :deep(.vxe-grid--toolbar-wrapper),
.oa-lite-unified-content-shell :deep(.vxe-table--header-wrapper),
.oa-lite-unified-content-shell :deep(.vxe-table--body-wrapper) {
  background: transparent;
}

.oa-lite-unified-content-shell :deep(.vxe-toolbar),
.oa-lite-unified-content-shell :deep(.vxe-grid--toolbar-wrapper) {
  border-radius: 0;
}

.oa-lite-unified-content-shell :deep(.vxe-grid) {
  border-left: 0 !important;
  border-right: 0 !important;
  border-radius: 0 !important;
}

.oa-lite-unified-content-shell :deep(.vxe-grid--toolbar-wrapper),
.oa-lite-unified-content-shell :deep(.vxe-table--header-wrapper) {
  border-left: 0 !important;
  border-right: 0 !important;
}

.oa-lite-unified-content-shell :deep(.ant-btn-primary) {
  border-color: var(--oa-accent);
  background: var(--oa-accent);
  color: var(--oa-accent-contrast);
  box-shadow: none;
}

.oa-lite-unified-content-shell :deep(.ant-input),
.oa-lite-unified-content-shell :deep(.ant-select-selector),
.oa-lite-unified-content-shell :deep(.ant-picker),
.oa-lite-unified-content-shell :deep(.ant-input-affix-wrapper) {
  border-radius: 0;
}

:deep(.oa-lite-settings-modal .ant-modal-content) {
  overflow: hidden;
  border-radius: 0;
  border: 1px solid var(--oa-shell-border);
  box-shadow: 0 10px 28px rgb(15 23 42 / 4%);
}

:deep(.oa-lite-settings-modal .ant-modal-body) {
  padding-top: 12px;
}

:deep(.oa-lite-settings-modal .ant-modal-header) {
  border-bottom: 1px solid var(--oa-shell-border);
  background: transparent;
}

.oa-lite-settings-sheet {
  display: grid;
  grid-template-columns: 280px minmax(0, 1fr);
  min-height: 620px;
}

.oa-lite-settings-sidebar {
  display: flex;
  min-width: 0;
  flex-direction: column;
  padding: 4px 20px 0 0;
  border-right: 1px solid var(--oa-shell-border);
}

.oa-lite-settings-sidebar-head {
  padding: 0 0 18px;
  border-bottom: 1px solid var(--oa-shell-border);
}

.oa-lite-settings-eyebrow {
  margin: 0 0 4px;
  color: var(--oa-ink-soft);
  font-size: 11px;
  font-weight: 700;
  letter-spacing: 0.08em;
  text-transform: uppercase;
}

.oa-lite-settings-sidebar-head h3 {
  margin: 0;
  color: var(--oa-ink);
  font-size: 20px;
  font-weight: 600;
  letter-spacing: normal;
}

.oa-lite-settings-sidebar-head p {
  margin: 8px 0 0;
  color: var(--oa-ink-soft);
  font-size: 13px;
  line-height: 1.6;
}

.oa-lite-settings-sidebar-nav {
  display: flex;
  flex-direction: column;
  gap: 0;
  padding-top: 14px;
}

.oa-lite-settings-pane-trigger {
  display: flex;
  width: 100%;
  padding: 12px 0;
  border: 0;
  border-bottom: 1px solid color-mix(in srgb, var(--oa-shell-border) 72%, transparent);
  background: transparent;
  color: var(--oa-ink-soft);
  text-align: left;
  transition:
    color 0.18s ease,
    border-color 0.18s ease,
    padding-left 0.18s ease;
  position: relative;
}

.oa-lite-settings-pane-trigger:hover,
.oa-lite-settings-pane-trigger.active {
  color: var(--oa-accent);
  border-bottom-color: color-mix(in srgb, var(--oa-accent) 26%, var(--oa-shell-border));
}

.oa-lite-settings-pane-trigger.active {
  padding-left: 12px;
}

.oa-lite-settings-pane-trigger.active::before {
  content: '';
  position: absolute;
  left: 0;
  top: 12px;
  bottom: 12px;
  width: 2px;
  background: var(--oa-accent);
}

.oa-lite-settings-pane-main {
  display: flex;
  min-width: 0;
  align-items: flex-start;
  gap: 10px;
}

.oa-lite-settings-pane-main :deep(svg) {
  margin-top: 2px;
  font-size: 16px;
}

.oa-lite-settings-pane-copy {
  display: flex;
  min-width: 0;
  flex: 1;
  flex-direction: column;
  gap: 3px;
}

.oa-lite-settings-pane-title {
  color: currentColor;
  font-size: 14px;
  font-weight: 600;
}

.oa-lite-settings-pane-desc {
  color: var(--oa-ink-faint);
  font-size: 12px;
  line-height: 1.5;
}

.oa-lite-settings-content {
  min-width: 0;
  padding: 4px 0 0 24px;
}

.oa-lite-settings-content-head {
  padding: 0 0 18px;
  border-bottom: 1px solid var(--oa-shell-border);
  margin-bottom: 18px;
}

.oa-lite-settings-content-title {
  color: var(--oa-ink);
  font-size: 24px;
  font-weight: 600;
  letter-spacing: -0.02em;
}

.oa-lite-settings-content-head p {
  margin: 8px 0 0;
  color: var(--oa-ink-soft);
  font-size: 13px;
  line-height: 1.6;
}

.oa-lite-settings-inline-stats {
  display: flex;
  flex-wrap: wrap;
  gap: 0;
}

.oa-lite-settings-inline-stat {
  display: flex;
  min-width: 132px;
  flex-direction: column;
  gap: 4px;
  padding: 0 18px 0 0;
  border-right: 1px solid color-mix(in srgb, var(--oa-shell-border) 72%, transparent);
  border-radius: 0;
  background: transparent;
}

.oa-lite-settings-inline-label {
  color: var(--oa-ink-soft);
  font-size: 11px;
  font-weight: 600;
}

.oa-lite-settings-inline-stat strong {
  color: var(--oa-ink);
  font-size: 15px;
  font-weight: 600;
}

.oa-lite-settings-section {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.oa-lite-settings-section + .oa-lite-settings-section {
  margin-top: 24px;
  padding-top: 20px;
  border-top: 1px solid var(--oa-shell-border);
}

.oa-lite-settings-section-head h4 {
  margin: 0;
  color: var(--oa-ink);
  font-size: 14px;
  font-weight: 600;
}

.oa-lite-settings-section-head p {
  margin: 4px 0 0;
  color: var(--oa-ink-soft);
  font-size: 13px;
}

.oa-lite-settings-list {
  display: flex;
  flex-direction: column;
  gap: 0;
}

.oa-lite-settings-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  width: 100%;
  padding: 14px 0;
  border: 0;
  border-bottom: 1px solid color-mix(in srgb, var(--oa-shell-border) 72%, transparent);
  background: transparent;
  text-align: left;
  transition:
    color 0.18s ease,
    border-color 0.18s ease,
    padding-left 0.18s ease;
  position: relative;
}

.oa-lite-settings-row:hover {
  color: var(--oa-accent);
  border-bottom-color: color-mix(in srgb, var(--oa-accent) 26%, var(--oa-shell-border));
  padding-left: 12px;
}

.oa-lite-settings-row:hover::before {
  content: '';
  position: absolute;
  left: 0;
  top: 14px;
  bottom: 14px;
  width: 2px;
  background: color-mix(in srgb, var(--oa-accent) 62%, transparent);
}

.oa-lite-settings-row-main {
  display: flex;
  min-width: 0;
  align-items: flex-start;
  gap: 12px;
}

.oa-lite-settings-row-main :deep(svg) {
  margin-top: 2px;
  font-size: 17px;
  color: currentColor;
}

.oa-lite-settings-row-copy {
  display: flex;
  min-width: 0;
  flex: 1;
  flex-direction: column;
  gap: 3px;
}

.oa-lite-settings-row-title {
  color: var(--oa-ink);
  font-size: 15px;
  font-weight: 600;
}

.oa-lite-settings-row-desc {
  color: var(--oa-ink-soft);
  font-size: 12px;
  line-height: 1.6;
}

.oa-lite-settings-row-meta {
  display: inline-flex;
  align-items: center;
  justify-content: center;
  color: var(--oa-ink-faint);
  font-size: 12px;
  text-align: right;
  word-break: break-all;
}

.oa-lite-settings-split-choice {
  display: grid;
  grid-template-columns: repeat(2, minmax(0, 1fr));
  gap: 16px;
}

.oa-lite-settings-choice {
  display: flex;
  min-height: 132px;
  flex-direction: column;
  justify-content: space-between;
  padding: 18px 0 16px;
  border: 0;
  border-top: 1px solid var(--oa-shell-border);
  border-bottom: 1px solid var(--oa-shell-border);
  background: transparent;
  text-align: left;
  transition:
    color 0.18s ease,
    border-color 0.18s ease,
    padding-left 0.18s ease;
  position: relative;
}

.oa-lite-settings-choice:hover,
.oa-lite-settings-choice.active {
  color: var(--oa-accent);
  border-top-color: color-mix(in srgb, var(--oa-accent) 26%, var(--oa-shell-border));
  border-bottom-color: color-mix(in srgb, var(--oa-accent) 26%, var(--oa-shell-border));
}

.oa-lite-settings-choice.active {
  padding-left: 12px;
}

.oa-lite-settings-choice.active::before {
  content: '';
  position: absolute;
  left: 0;
  top: 18px;
  bottom: 18px;
  width: 2px;
  background: var(--oa-accent);
}

.oa-lite-settings-choice-title {
  color: var(--oa-ink);
  font-size: 18px;
  font-weight: 600;
}

.oa-lite-settings-choice-desc {
  color: var(--oa-ink-soft);
  font-size: 13px;
  line-height: 1.6;
}

@media (max-width: 960px) {
  .oa-lite-unified-topbar {
    grid-template-columns: 1fr;
  }

  .oa-lite-unified-main {
    flex-direction: column;
  }

  .oa-lite-unified-sidebar {
    width: 100%;
  }

  .oa-lite-unified-resizer {
    display: none;
  }

  .oa-lite-unified-sidebar-card,
  .oa-lite-unified-content {
    height: auto;
    min-height: calc(100vh - 180px);
  }

  .oa-lite-settings-sheet {
    grid-template-columns: 1fr;
  }

  .oa-lite-settings-sidebar {
    padding-right: 0;
    padding-bottom: 18px;
    border-right: 0;
    border-bottom: 1px solid var(--oa-shell-border);
  }

  .oa-lite-settings-content {
    padding-left: 0;
  }

  .oa-lite-settings-split-choice {
    grid-template-columns: 1fr;
  }
}

@media (max-width: 768px) {
  .oa-lite-unified-topbar,
  .oa-lite-unified-main {
    padding-right: 16px;
    padding-left: 16px;
  }

  .oa-lite-unified-actions {
    flex-wrap: wrap;
    justify-content: flex-end;
  }
}
</style>
