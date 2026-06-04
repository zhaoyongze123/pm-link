<script lang="ts" setup>
import type { BpmCategoryApi } from '#/api/bpm/category';
import type { BpmProcessDefinitionApi } from '#/api/bpm/definition';
import type { BpmProcessInstanceApi } from '#/api/bpm/processInstance';
import type { BpmTaskApi } from '#/api/bpm/task';
import type { SystemUserApi } from '#/api/system/user';
import type { NotificationItem } from '@vben/layouts';

import {
  computed,
  nextTick,
  onMounted,
  onUnmounted,
  reactive,
  ref,
  watch,
} from 'vue';

import {
  BpmCandidateStrategyEnum,
  BpmNodeIdEnum,
  BpmProcessInstanceStatus,
} from '@vben/constants';
import { VbenFullScreen } from '@vben/common-ui';
import { getDictOptions } from '@vben/hooks';
import {
  AntdProfileOutlined,
  IconifyIcon,
} from '@vben/icons';
import {
  LanguageToggle,
  Notification,
  ThemeToggle,
  TimezoneButton,
  UserDropdown,
} from '@vben/layouts';
import { useI18n } from '@vben/locales';
import { preferences } from '@vben/preferences';
import { useAccessStore, useUserStore } from '@vben/stores';
import { formatDateTime, formatPast2 } from '@vben/utils';
import { useWebSocket } from '@vueuse/core';

import {
  Button,
  ConfigProvider,
  DatePicker,
  Empty,
  Form,
  Input,
  message,
  Pagination,
  Select,
  Spin,
  Tag,
  theme as antdTheme,
} from 'ant-design-vue';
import dayjs from 'dayjs';

import { getCategorySimpleList } from '#/api/bpm/category';
import { getProcessDefinition, getProcessDefinitionList } from '#/api/bpm/definition';
import { createDocument, getDocument } from '#/api/bpm/oa/document';
import { createProject, getProject } from '#/api/bpm/oa/project';
import { createLeave, getLeave } from '#/api/bpm/oa/leave';
import { createStaffing, getStaffing } from '#/api/bpm/oa/staffing';
import {
  getApprovalDetail,
  getProcessInstanceCopyPage,
  getProcessInstanceMyPage,
} from '#/api/bpm/processInstance';
import { requestClient } from '#/api/request';
import {
  getUnreadNotifyMessageCount,
  getUnreadNotifyMessageList,
  updateAllNotifyMessageRead,
  updateNotifyMessageRead,
} from '#/api/system/notify/message';
import { getUserProfile } from '#/api/system/user/profile';
import { router } from '#/router';
import { getSimpleUserList } from '#/api/system/user';
import { getTaskDonePage, getTaskTodoPage } from '#/api/bpm/task';
import { useAuthStore } from '#/store';
import ProcessInstanceTimeline from '#/views/bpm/processInstance/detail/modules/time-line.vue';
import ProfileCenter from '#/views/_core/profile/index.vue';
import ProcessDetail, {
  type OaLiteDetailRequest,
  type OaLiteDetailSection,
} from './components/process-detail.vue';
import OaLiteComplexTemplateForm from './components/complex-template-form.vue';

defineOptions({ name: 'OALiteHome' });

type MainTab = 'create' | 'copied' | 'initiated' | 'pending' | 'processed';
type ListTab = Exclude<MainTab, 'create'>;
type ViewState = 'complex-form' | 'leave-form' | 'main' | 'profile';
type DateRangeValue = [string, string];
type OaTemplateKey =
  | 'attendance'
  | 'document'
  | 'expense'
  | 'leave'
  | 'overtime'
  | 'project'
  | 'seal'
  | 'staffing'
  | 'trip';

interface OaTaskAssignedWebSocketMessage {
  assigneeUserId: number;
  processInstanceId: string;
  processInstanceName: string;
  startUserId: number;
  startUserNickname: string;
  taskId: string;
  taskName: string;
}

interface ListFilterState {
  category?: string;
  createTime?: DateRangeValue;
  name: string;
  processDefinitionId?: string;
  processDefinitionKey?: string;
  status?: number;
}

interface ListPageState {
  pageNo: number;
  pageSize: number;
  total: number;
}

interface LeaveFormState {
  endTime: string;
  reason: string;
  startTime: string;
  startUserSelectAssignees: Record<string, number[]>;
  type?: number;
}

interface SelectOption {
  label: string;
  value: number | string;
}

interface OaTemplateConfig {
  createMode?: 'inline' | 'route';
  createRequest: (data: Record<string, any>) => Promise<unknown>;
  description: string;
  endTimeLabel: string;
  endTimePlaceholder: string;
  getDetailRequest: (id: number) => Promise<Record<string, any>>;
  icon: string;
  key: OaTemplateKey;
  processKey: string;
  reasonLabel: string;
  reasonPlaceholder: string;
  routeName?: string;
  submitLabel: string;
  startTimeLabel: string;
  startTimePlaceholder: string;
  subtitle: string;
  title: string;
  typeLabel: string;
  typeOptions: SelectOption[];
  typePlaceholder: string;
}

interface OaTemplateCard extends OaTemplateConfig {
  definition: BpmProcessDefinitionApi.ProcessDefinition;
}

type DetailPayload =
  | BpmTaskApi.Task
  | BpmProcessInstanceApi.ProcessInstance
  | BpmProcessInstanceApi.ProcessInstanceCopyRespVO
  | null;

const LEAVE_PROCESS_KEY = 'oa_leave';
const DEFAULT_PAGE_SIZE = 20;
const listTabs: ListTab[] = ['initiated', 'pending', 'processed', 'copied'];
const createTemplateRequest = (processKey: string, data: Record<string, any>) =>
  requestClient.post(`/bpm/oa/${processKey}/create`, data);
const getTemplateDetailRequest = (processKey: string, id: number) =>
  requestClient.get<Record<string, any>>(`/bpm/oa/${processKey}/get?id=${id}`);
const OA_TEMPLATE_CONFIGS: OaTemplateConfig[] = [
  {
    createRequest: (data) => createTemplateRequest('leave', data),
    description: '发起真实请假审批流程',
    endTimeLabel: '结束时间',
    endTimePlaceholder: '请选择结束时间',
    getDetailRequest: (id) => getTemplateDetailRequest('leave', id),
    icon: 'lucide:file-heart',
    key: 'leave',
    processKey: 'oa_leave',
    reasonLabel: '请假原因',
    reasonPlaceholder: '请输入请假原因',
    submitLabel: '提交请假审批',
    startTimeLabel: '开始时间',
    startTimePlaceholder: '请选择开始时间',
    subtitle: '真实 BPM 流程发起',
    title: '请假',
    typeLabel: '请假类型',
    typeOptions: [
      { label: '病假', value: 1 },
      { label: '事假', value: 2 },
      { label: '婚假', value: 3 },
    ],
    typePlaceholder: '请选择请假类型',
  },
  {
    createRequest: (data) => createTemplateRequest('trip', data),
    description: '发起出差申请流程',
    endTimeLabel: '结束时间',
    endTimePlaceholder: '请选择结束时间',
    getDetailRequest: (id) => getTemplateDetailRequest('trip', id),
    icon: 'lucide:map-pinned',
    key: 'trip',
    processKey: 'oa_trip',
    reasonLabel: '出差事由',
    reasonPlaceholder: '请输入出差事由',
    submitLabel: '提交出差审批',
    startTimeLabel: '开始时间',
    startTimePlaceholder: '请选择开始时间',
    subtitle: '真实 BPM 流程发起',
    title: '出差',
    typeLabel: '出差类型',
    typeOptions: [
      { label: '项目调研', value: 1 },
      { label: '汇报对接', value: 2 },
      { label: '外地驻场', value: 3 },
    ],
    typePlaceholder: '请选择出差类型',
  },
  {
    createRequest: (data) => createTemplateRequest('overtime', data),
    description: '发起加班申请流程',
    endTimeLabel: '结束时间',
    endTimePlaceholder: '请选择结束时间',
    getDetailRequest: (id) => getTemplateDetailRequest('overtime', id),
    icon: 'lucide:clock-3',
    key: 'overtime',
    processKey: 'oa_overtime',
    reasonLabel: '加班事由',
    reasonPlaceholder: '请输入加班事由',
    submitLabel: '提交加班审批',
    startTimeLabel: '开始时间',
    startTimePlaceholder: '请选择开始时间',
    subtitle: '真实 BPM 流程发起',
    title: '加班',
    typeLabel: '加班类型',
    typeOptions: [
      { label: '工作日加班', value: 1 },
      { label: '周末加班', value: 2 },
      { label: '节假日加班', value: 3 },
    ],
    typePlaceholder: '请选择加班类型',
  },
  {
    createRequest: (data) => createTemplateRequest('attendance', data),
    description: '发起补卡申请流程',
    endTimeLabel: '补卡时间',
    endTimePlaceholder: '请选择补卡时间',
    getDetailRequest: (id) => getTemplateDetailRequest('attendance', id),
    icon: 'lucide:badge-check',
    key: 'attendance',
    processKey: 'oa_attendance',
    reasonLabel: '补卡说明',
    reasonPlaceholder: '请输入补卡说明',
    submitLabel: '提交补卡审批',
    startTimeLabel: '原打卡时间',
    startTimePlaceholder: '请选择原打卡时间',
    subtitle: '真实 BPM 流程发起',
    title: '补卡',
    typeLabel: '补卡类型',
    typeOptions: [
      { label: '上班漏打卡', value: 1 },
      { label: '下班漏打卡', value: 2 },
      { label: '外勤补卡', value: 3 },
    ],
    typePlaceholder: '请选择补卡类型',
  },
  {
    createMode: 'route',
    createRequest: (data) => createDocument(data),
    description: '进入复杂合同/文件审批表单',
    endTimeLabel: '结束时间',
    endTimePlaceholder: '请选择结束时间',
    getDetailRequest: (id) => getDocument(id),
    icon: 'lucide:file-signature',
    key: 'document',
    processKey: 'oa_document',
    reasonLabel: '审批事由',
    reasonPlaceholder: '请输入审批事由',
    routeName: 'OADocumentCreate',
    submitLabel: '提交合同/文件审批',
    startTimeLabel: '开始时间',
    startTimePlaceholder: '请选择开始时间',
    subtitle: '复杂业务表单',
    title: '合同/文件审批',
    typeLabel: '文件类型',
    typeOptions: [
      { label: '合同', value: '合同' },
      { label: '函件', value: '函件' },
      { label: '请示', value: '请示' },
    ],
    typePlaceholder: '请选择文件类型',
  },
  {
    createRequest: (data) => createTemplateRequest('expense', data),
    description: '发起报销申请流程',
    endTimeLabel: '报销结束时间',
    endTimePlaceholder: '请选择报销结束时间',
    getDetailRequest: (id) => getTemplateDetailRequest('expense', id),
    icon: 'lucide:receipt-text',
    key: 'expense',
    processKey: 'oa_expense',
    reasonLabel: '报销说明',
    reasonPlaceholder: '请输入报销说明',
    submitLabel: '提交报销审批',
    startTimeLabel: '报销开始时间',
    startTimePlaceholder: '请选择报销开始时间',
    subtitle: '真实 BPM 流程发起',
    title: '报销',
    typeLabel: '报销类型',
    typeOptions: [
      { label: '差旅费', value: 1 },
      { label: '办公费', value: 2 },
      { label: '接待费', value: 3 },
    ],
    typePlaceholder: '请选择报销类型',
  },
  {
    createMode: 'route',
    createRequest: (data) => createProject(data),
    description: '进入复杂项目立项申请表单',
    endTimeLabel: '结束时间',
    endTimePlaceholder: '请选择结束时间',
    getDetailRequest: (id) => getProject(id),
    icon: 'lucide:folder-plus',
    key: 'project',
    processKey: 'oa_project',
    reasonLabel: '立项说明',
    reasonPlaceholder: '请输入立项说明',
    routeName: 'OAProjectCreate',
    submitLabel: '提交项目立项申请',
    startTimeLabel: '开始时间',
    startTimePlaceholder: '请选择开始时间',
    subtitle: '复杂业务表单',
    title: '项目立项申请',
    typeLabel: '项目类型',
    typeOptions: [
      { label: '总体规划', value: '总体规划' },
      { label: '详细规划', value: '详细规划' },
      { label: '专项规划', value: '专项规划' },
    ],
    typePlaceholder: '请选择项目类型',
  },
  {
    createMode: 'route',
    createRequest: (data) => createTemplateRequest('seal', data),
    description: '进入复杂用章申请表单',
    endTimeLabel: '用章结束时间',
    endTimePlaceholder: '请选择用章结束时间',
    getDetailRequest: (id) => getTemplateDetailRequest('seal', id),
    icon: 'lucide:stamp',
    key: 'seal',
    processKey: 'oa_seal',
    routeName: 'OASealCreate',
    reasonLabel: '用章事由',
    reasonPlaceholder: '请输入用章事由',
    submitLabel: '提交用章审批',
    startTimeLabel: '用章开始时间',
    startTimePlaceholder: '请选择用章开始时间',
    subtitle: '真实 BPM 流程发起',
    title: '用章',
    typeLabel: '用章类型',
    typeOptions: [
      { label: '公章', value: 1 },
      { label: '合同章', value: 2 },
      { label: '财务章', value: 3 },
    ],
    typePlaceholder: '请选择用章类型',
  },
  {
    createMode: 'route',
    createRequest: (data) => createStaffing(data),
    description: '进入复杂项目人员调配表单',
    endTimeLabel: '结束时间',
    endTimePlaceholder: '请选择结束时间',
    getDetailRequest: (id) => getStaffing(id),
    icon: 'lucide:users-round',
    key: 'staffing',
    processKey: 'oa_staffing',
    reasonLabel: '调配原因',
    reasonPlaceholder: '请输入调配原因',
    routeName: 'OAStaffingCreate',
    submitLabel: '提交项目人员调配申请',
    startTimeLabel: '开始时间',
    startTimePlaceholder: '请选择开始时间',
    subtitle: '复杂业务表单',
    title: '项目人员调配申请',
    typeLabel: '调配类型',
    typeOptions: [
      { label: '项目增补', value: 1 },
      { label: '项目调出', value: 2 },
      { label: '阶段支援', value: 3 },
    ],
    typePlaceholder: '请选择调配类型',
  },
];

const authStore = useAuthStore();
const accessStore = useAccessStore();
const userStore = useUserStore();
const { t } = useI18n();
const refreshToken = accessStore.refreshToken as string;

const loading = ref(false);
const leaveSubmitting = ref(false);
const leavePublishing = ref(false);
const complexFormBusinessKey = ref<string>();
const activeTab = ref<MainTab>('create');
const currentTemplateKey = ref<OaTemplateKey>('leave');
const lastCenterTab = ref<ListTab>('pending');
const viewState = ref<ViewState>('main');
const selectedCreateCategoryCode = ref<string>();
const selectedItem = ref<DetailPayload>(null);
const categories = ref<BpmCategoryApi.Category[]>([]);
const leaveProcessDefinition = ref<BpmProcessDefinitionApi.ProcessDefinition | null>(
  null,
);
const processDefinitions = ref<
  Partial<Record<OaTemplateKey, BpmProcessDefinitionApi.ProcessDefinition | null>>
>({});
const oaTemplateDefinitions = ref<BpmProcessDefinitionApi.ProcessDefinition[]>([]);
const selectableUsers = ref<SystemUserApi.User[]>([]);
const activityNodes = ref<BpmProcessInstanceApi.ApprovalNodeInfo[]>([]);
const startUserSelectTasks = ref<BpmProcessInstanceApi.ApprovalNodeInfo[]>([]);
const timelineRef = ref<any>();
const todoItems = ref<BpmTaskApi.Task[]>([]);
const doneItems = ref<BpmTaskApi.Task[]>([]);
const initiatedItems = ref<BpmProcessInstanceApi.ProcessInstance[]>([]);
const copiedItems = ref<BpmProcessInstanceApi.ProcessInstanceCopyRespVO[]>([]);
const OA_LITE_BODY_THEME_CLASS = 'oa-lite-light-theme';
const OA_LITE_TASK_ASSIGNED_MESSAGE_TYPE = 'task-assigned';
const OA_LITE_TASK_ASSIGNED_TOAST_KEY = 'oa-lite-task-assigned';
const OA_LITE_TASK_ASSIGNED_NOTIFICATION_PREFIX = 'oa-lite-task-assigned:';
const headerNotifications = ref<NotificationItem[]>([]);
const realtimeNotifications = ref<NotificationItem[]>([]);
const headerUnreadCount = ref(0);
const mergedNotifications = computed(() => [
  ...realtimeNotifications.value,
  ...headerNotifications.value,
]);
const showNotificationDot = computed(
  () =>
    realtimeNotifications.value.some((item) => !item.isRead) ||
    headerUnreadCount.value > 0,
);
let notificationPollingTimer: null | ReturnType<typeof setInterval> = null;
const webSocketServer = `${`${import.meta.env.VITE_BASE_URL}/infra/ws`.replace(
  'http',
  'ws',
)}?token=${refreshToken}`;
const { data: webSocketData, close: closeWebSocket } = useWebSocket(
  webSocketServer,
  {
    autoReconnect: true,
    heartbeat: true,
  },
);

const oaLiteTheme = {
  algorithm: [antdTheme.defaultAlgorithm],
  token: {
    colorBgBase: '#ffffff',
    colorBgContainer: '#ffffff',
    colorBgElevated: '#ffffff',
    colorBorder: '#dbe5f0',
    colorBorderSecondary: '#e5edf5',
    colorFillSecondary: '#f8fafc',
    colorFillTertiary: '#f1f5f9',
    colorPrimary: '#2563eb',
    colorPrimaryActive: '#1e40af',
    colorPrimaryHover: '#1d4ed8',
    colorSplit: '#e5e7eb',
    colorText: '#111827',
    colorTextQuaternary: '#94a3b8',
    colorTextSecondary: '#475569',
    colorTextTertiary: '#64748b',
  },
};

const headerMenus = computed(() => [
  {
    handler: () => {
      openProfileCenter();
    },
    icon: AntdProfileOutlined,
    text: t('page.oaLite.profileCenter.title'),
  },
]);

const avatar = computed(
  () => userStore.userInfo?.avatar ?? preferences.app.defaultAvatar,
);

async function syncCurrentUserProfile() {
  const profile = await getUserProfile().catch(() => null);
  if (!profile) {
    return;
  }
  userStore.setUserInfo({
    ...(userStore.userInfo ?? {}),
    avatar: profile?.avatar || userStore.userInfo?.avatar || '',
    email: profile?.email ?? userStore.userInfo?.email,
    nickname: profile?.nickname ?? userStore.userInfo?.nickname ?? '',
    userId:
      String(userStore.userInfo?.userId ?? profile?.id ?? '') || '',
    username: profile?.username ?? userStore.userInfo?.username ?? '',
  });
}

const tabLoading = reactive<Record<ListTab, boolean>>({
  copied: false,
  initiated: false,
  pending: false,
  processed: false,
});
const tabInitialized = reactive<Record<ListTab, boolean>>({
  copied: false,
  initiated: false,
  pending: false,
  processed: false,
});
const tabPages = reactive<Record<ListTab, ListPageState>>({
  copied: {
    pageNo: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    total: 0,
  },
  initiated: {
    pageNo: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    total: 0,
  },
  pending: {
    pageNo: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    total: 0,
  },
  processed: {
    pageNo: 1,
    pageSize: DEFAULT_PAGE_SIZE,
    total: 0,
  },
});

const leaveForm = reactive<LeaveFormState>({
  endTime: '',
  reason: '',
  startTime: '',
  startUserSelectAssignees: {},
  type: undefined,
});

function createDefaultFilter(): ListFilterState {
  return {
    category: undefined,
    createTime: undefined,
    name: '',
    processDefinitionId: undefined,
    processDefinitionKey: undefined,
    status: undefined,
  };
}

const listFilters = reactive<Record<ListTab, ListFilterState>>({
  copied: createDefaultFilter(),
  initiated: createDefaultFilter(),
  pending: createDefaultFilter(),
  processed: createDefaultFilter(),
});

function normalizeDictOptions(dictType: string) {
  return getDictOptions(dictType, 'number')
    .filter(
      (item) =>
        typeof item.value === 'number' || typeof item.value === 'string',
    )
    .map((item) => ({
      label: String(item.label),
      value: item.value as number | string,
    })) as SelectOption[];
}

const leaveTypeOptions = computed<SelectOption[]>(() =>
  normalizeDictOptions('bpm_oa_leave_type'),
);
const processStatusFallbackOptions: SelectOption[] = [
  {
    label: t('page.oaLite.status.running'),
    value: BpmProcessInstanceStatus.RUNNING,
  },
  {
    label: t('page.oaLite.status.approved'),
    value: BpmProcessInstanceStatus.APPROVE,
  },
  {
    label: t('page.oaLite.status.rejected'),
    value: BpmProcessInstanceStatus.REJECT,
  },
  {
    label: t('page.oaLite.status.cancelled'),
    value: BpmProcessInstanceStatus.CANCEL,
  },
];
const taskStatusFallbackOptions: SelectOption[] = [
  {
    label: t('page.oaLite.status.running'),
    value: 1,
  },
  {
    label: t('page.oaLite.status.approved'),
    value: 2,
  },
  {
    label: t('page.oaLite.status.rejected'),
    value: 3,
  },
  {
    label: t('page.oaLite.status.cancelled'),
    value: 4,
  },
];
const currentTemplateConfig = computed(
  () =>
    OA_TEMPLATE_CONFIGS.find((item) => item.key === currentTemplateKey.value) ||
    OA_TEMPLATE_CONFIGS[0],
);
const currentTemplateDefinition = computed(
  () => processDefinitions.value[currentTemplateKey.value] || null,
);
const currentTemplateTypeOptions = computed<SelectOption[]>(() =>
  currentTemplateKey.value === 'leave'
    ? (leaveTypeOptions.value.length > 0
        ? leaveTypeOptions.value
        : currentTemplateConfig.value.typeOptions)
    : currentTemplateConfig.value.typeOptions,
);
const processStatusOptions = computed<SelectOption[]>(() =>
  normalizeDictOptions('bpm_process_instance_status').length > 0
    ? normalizeDictOptions('bpm_process_instance_status')
    : processStatusFallbackOptions,
);
const taskStatusOptions = computed<SelectOption[]>(() =>
  normalizeDictOptions('bpm_task_status').length > 0
    ? normalizeDictOptions('bpm_task_status')
    : taskStatusFallbackOptions,
);
const categoryOptions = computed<SelectOption[]>(() =>
  categories.value.map((item) => ({
    label: item.name,
    value: item.code,
  })),
);
const availableTemplateDefinitions = computed<OaTemplateCard[]>(() => {
  const configMap = new Map(
    OA_TEMPLATE_CONFIGS.map((item) => [item.processKey, item] as const),
  );
  return oaTemplateDefinitions.value
    .map((definition) => {
      const config = configMap.get(definition.key || '');
      if (!config) {
        return null;
      }
      return {
        ...config,
        definition,
      } satisfies OaTemplateCard;
    })
    .filter(Boolean) as OaTemplateCard[];
});
const processTemplateIdOptions = computed<SelectOption[]>(() =>
  availableTemplateDefinitions.value.map((item) => ({
    label: item.definition.name,
    value: item.definition.id,
  })),
);
const processTemplateKeyOptions = computed<SelectOption[]>(() =>
  availableTemplateDefinitions.value.map((item) => ({
    label: item.definition.name,
    value: item.processKey,
  })),
);
const currentStatusOptions = computed<SelectOption[]>(() =>
  activeTab.value === 'processed'
    ? taskStatusOptions.value
    : processStatusOptions.value,
);
const selectApproverLabel = computed(() =>
  JSON.stringify(t('page.oaLite.timeline.selectApprover')),
);
const currentProcessOptions = computed<SelectOption[]>(() =>
  activeTab.value === 'copied'
    ? processTemplateIdOptions.value
    : processTemplateKeyOptions.value,
);
const currentProcessFilterValue = computed<string | undefined>({
  get() {
    if (activeTab.value === 'create') {
      return undefined;
    }
    return activeTab.value === 'copied'
      ? listFilters.copied.processDefinitionId
      : listFilters[activeTab.value].processDefinitionKey;
  },
  set(value) {
    if (activeTab.value === 'create') {
      return;
    }
    if (activeTab.value === 'copied') {
      listFilters.copied.processDefinitionId = value;
      return;
    }
    listFilters[activeTab.value].processDefinitionKey = value;
  },
});

const currentFilter = computed(() =>
  activeTab.value === 'create' ? null : listFilters[activeTab.value],
);
const currentPageState = computed(() =>
  activeTab.value === 'create' ? null : tabPages[activeTab.value],
);
const currentListLoading = computed(() =>
  activeTab.value === 'create' ? false : tabLoading[activeTab.value],
);
const currentDetailSection = computed<OaLiteDetailSection>(() =>
  activeTab.value === 'create' ? 'initiated' : activeTab.value,
);

const stats = computed(() => ({
  copied: tabPages.copied.total,
  initiated: tabPages.initiated.total,
  pending: tabPages.pending.total,
  processed: new Set(
    doneItems.value
      .map((item) => item.processInstanceId || item.processInstance?.id)
      .filter(Boolean),
  ).size,
}));

const createCategoryTabs = computed<BpmCategoryApi.Category[]>(() => {
  const categoryMap = new Map<string, BpmCategoryApi.Category>();
  availableTemplateDefinitions.value.forEach((item, index) => {
    const definition = item.definition;
    categoryMap.set(definition.category, {
      code: definition.category,
      description: undefined,
      id: index + 1,
      name:
        definition.categoryName ||
        categories.value.find((category) => category.code === definition.category)?.name ||
        t('page.oaLite.misc.uncategorized'),
      sort: index,
      status: 0,
    });
  });
  return [...categoryMap.values()];
});

const currentCreateCategoryCode = computed(() => selectedCreateCategoryCode.value);
const createCategorySections = computed(() =>
  createCategoryTabs.value.map((category) => ({
    ...category,
    templates: availableTemplateDefinitions.value.filter(
      (item) => item.definition.category === category.code,
    ),
  })),
);
const createCategorySectionElements = ref<Record<string, HTMLElement | null>>({});

const dashboardNavItems = computed(() => [
  {
    count: stats.value.pending,
    icon: 'lucide:list-todo',
    key: 'pending' as ListTab,
    label: t('page.oaLite.nav.pending'),
  },
  {
    count: stats.value.processed,
    icon: 'lucide:badge-check',
    key: 'processed' as ListTab,
    label: t('page.oaLite.nav.processed'),
  },
  {
    count: stats.value.initiated,
    icon: 'lucide:file-text',
    key: 'initiated' as ListTab,
    label: t('page.oaLite.nav.initiated'),
  },
  {
    count: stats.value.copied,
    icon: 'lucide:send',
    key: 'copied' as ListTab,
    label: t('page.oaLite.nav.copied'),
  },
]);

const topNavKey = computed<'center' | 'create'>(() =>
  activeTab.value === 'create' ? 'create' : 'center',
);

const currentListTitle = computed(() => {
  switch (activeTab.value) {
    case 'copied': {
      return t('page.oaLite.center.copiedTitle');
    }
    case 'initiated': {
      return t('page.oaLite.center.initiatedTitle');
    }
    case 'pending': {
      return t('page.oaLite.center.pendingTitle');
    }
    case 'processed': {
      return t('page.oaLite.center.processedTitle');
    }
    default: {
      return t('page.oaLite.center.createTitle');
    }
  }
});

const currentListSubtitle = computed(() => {
  switch (activeTab.value) {
    case 'copied': {
      return t('page.oaLite.center.copiedSubtitle');
    }
    case 'initiated': {
      return t('page.oaLite.center.initiatedSubtitle');
    }
    case 'pending': {
      return t('page.oaLite.center.pendingSubtitle');
    }
    case 'processed': {
      return t('page.oaLite.center.processedSubtitle');
    }
    default: {
      return t('page.oaLite.center.createSubtitle');
    }
  }
});

const showProcessFilter = computed(
  () =>
    activeTab.value === 'initiated' ||
    activeTab.value === 'pending' ||
    activeTab.value === 'processed',
);
const showCategoryFilter = computed(
  () =>
    activeTab.value === 'initiated' ||
    activeTab.value === 'pending' ||
    activeTab.value === 'processed',
);
const showStatusFilter = computed(
  () => activeTab.value === 'initiated' || activeTab.value === 'processed',
);

const currentList = computed(() => {
  if (activeTab.value === 'create') {
    return [];
  }
  return getListSource(activeTab.value);
});

const currentDetailRequest = computed<null | OaLiteDetailRequest>(() => {
  if (!selectedItem.value) {
    return null;
  }
  if (isTaskItem(selectedItem.value)) {
    return {
      businessKey: selectedItem.value.processInstance?.businessKey,
      processInstanceId: String(
        selectedItem.value.processInstance?.id || selectedItem.value.processInstanceId,
      ),
      taskId: selectedItem.value.id,
    };
  }
  if (isCopiedItem(selectedItem.value)) {
    return {
      activityId: selectedItem.value.activityId || undefined,
      processInstanceId: String(selectedItem.value.processInstanceId),
      taskId: selectedItem.value.taskId || undefined,
    };
  }
  return {
    businessKey: selectedItem.value.businessKey,
    processInstanceId: String(selectedItem.value.id),
  };
});

function isTaskItem(item: DetailPayload): item is BpmTaskApi.Task {
  return Boolean(item && 'processInstance' in item);
}

function isCopiedItem(
  item: DetailPayload,
): item is BpmProcessInstanceApi.ProcessInstanceCopyRespVO {
  return Boolean(item && 'processInstanceId' in item && 'activityName' in item);
}

function getListSource(tab: ListTab) {
  switch (tab) {
    case 'copied': {
      return copiedItems.value;
    }
    case 'initiated': {
      return initiatedItems.value;
    }
    case 'pending': {
      return todoItems.value;
    }
    case 'processed': {
      return doneItems.value;
    }
  }
}

function getItemIdentity(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isCopiedItem(item)) {
    return `copy-${item.id}-${item.processInstanceId}-${item.activityId}`;
  }
  if (isTaskItem(item)) {
    return `task-${item.id}`;
  }
  return `process-${item.id}`;
}

function syncSelectedItem(tab: ListTab) {
  const list = getListSource(tab);
  const currentIdentity = getItemIdentity(selectedItem.value);
  const found = currentIdentity
    ? list.find((item) => getItemIdentity(item) === currentIdentity)
    : undefined;
  selectedItem.value = found || list[0] || null;
}

function getSummaryText(summary?: { key: string; value: string }[]) {
  if (!summary?.length) {
    return t('page.oaLite.misc.emptySummary');
  }
  return summary.map((item) => `${item.key}：${item.value}`).join(' / ');
}

function getProcessStatusText(status?: number) {
  switch (status) {
    case BpmProcessInstanceStatus.APPROVE: {
      return t('page.oaLite.status.approved');
    }
    case BpmProcessInstanceStatus.CANCEL: {
      return t('page.oaLite.status.cancelled');
    }
    case BpmProcessInstanceStatus.REJECT: {
      return t('page.oaLite.status.rejected');
    }
    case BpmProcessInstanceStatus.RUNNING: {
      return t('page.oaLite.status.running');
    }
    default: {
      return t('page.oaLite.status.processing');
    }
  }
}

function getTaskStatusText(status?: number) {
  const option = taskStatusOptions.value.find((item) => item.value === status);
  return option?.label || t('page.oaLite.status.processed');
}

function dedupeDoneTasks(tasks: BpmTaskApi.Task[]) {
  const taskMap = new Map<string, BpmTaskApi.Task>();
  tasks.forEach((task) => {
    const processInstanceId = String(
      task.processInstanceId || task.processInstance?.id || '',
    );
    if (!processInstanceId) {
      taskMap.set(`task-${task.id}`, task);
      return;
    }
    const current = taskMap.get(processInstanceId);
    if (!current) {
      taskMap.set(processInstanceId, task);
      return;
    }
    const currentTime = new Date(current.endTime || current.createTime || 0).getTime();
    const nextTime = new Date(task.endTime || task.createTime || 0).getTime();
    if (nextTime >= currentTime) {
      taskMap.set(processInstanceId, task);
    }
  });
  return [...taskMap.values()];
}

function getItemStatus(item: DetailPayload) {
  if (!item) {
    return undefined;
  }
  if (isTaskItem(item)) {
    return item.processInstance?.status ?? item.status;
  }
  if (isCopiedItem(item)) {
    return undefined;
  }
  return item.status;
}

function getItemStatusText(item: DetailPayload) {
  if (!item) {
    return '';
  }
  const status = getItemStatus(item);
  if (status === undefined) {
    return '';
  }
  return getProcessStatusText(status);
}

function getItemStatusTone(item: DetailPayload) {
  const status = getItemStatus(item);
  switch (status) {
    case BpmProcessInstanceStatus.APPROVE: {
      return 'success';
    }
    case BpmProcessInstanceStatus.REJECT: {
      return 'danger';
    }
    case BpmProcessInstanceStatus.CANCEL: {
      return 'muted';
    }
    case BpmProcessInstanceStatus.RUNNING: {
      return 'warning';
    }
    default: {
      return 'neutral';
    }
  }
}

function getItemTitle(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isTaskItem(item)) {
    return item.processInstance?.name || '';
  }
  if (isCopiedItem(item)) {
    return item.processInstanceName || '';
  }
  return item.name || '';
}

function getItemSummary(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isTaskItem(item)) {
    return getSummaryText(item.processInstance?.summary as any);
  }
  if (isCopiedItem(item)) {
    return getSummaryText(item.summary as any);
  }
  return getSummaryText(item.summary);
}

function getItemMetaLeft(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isTaskItem(item)) {
    return `${t('page.oaLite.item.currentTask')}：${item.name}`;
  }
  if (isCopiedItem(item)) {
    return `${t('page.oaLite.item.copyNode')}：${item.activityName || '-'}`;
  }
  if (
    item.status === BpmProcessInstanceStatus.RUNNING &&
    item.tasks &&
    item.tasks.length > 0
  ) {
    const firstTask = item.tasks[0];
    if (!firstTask) {
      return getProcessStatusText(item.status);
    }
    if (item.tasks.length === 1) {
      return `${firstTask.assigneeUser?.nickname || t('page.oaLite.item.approver')}（${firstTask.name}）${t('page.oaLite.status.running')}`;
    }
    return `${firstTask.assigneeUser?.nickname || t('page.oaLite.item.approver')} ${t('page.oaLite.item.andCount', [item.tasks.length])}（${firstTask.name}）${t('page.oaLite.status.running')}`;
  }
  return getProcessStatusText(item.status);
}

function getItemMetaRight(item: DetailPayload) {
  if (!item) {
    return '';
  }
  if (isTaskItem(item)) {
    return activeTab.value === 'processed'
      ? `${t('page.oaLite.item.finishTime')}：${formatDateTime(item.endTime || item.createTime)}`
      : `${t('page.oaLite.item.taskTime')}：${formatDateTime(item.createTime)}`;
  }
  if (isCopiedItem(item)) {
    return `${t('page.oaLite.item.copyTime')}：${formatDateTime(item.createTime)}`;
  }
  return activeTab.value === 'initiated'
    ? `${t('page.oaLite.item.startTime')}：${formatDateTime(item.startTime || item.createTime)}`
    : `${t('page.oaLite.item.endTime')}：${formatDateTime(item.endTime || item.createTime)}`;
}

function getExtraMetaRows(item: DetailPayload) {
  if (!item) {
    return [] as string[];
  }
  if (isCopiedItem(item)) {
    return [
      `${t('page.oaLite.item.processStarter')}：${item.startUser?.nickname || '-'}`,
      `${t('page.oaLite.item.copyUser')}：${item.createUser?.nickname || '-'}`,
      `${t('page.oaLite.item.copyReason')}：${item.reason || '-'}`,
    ];
  }
  if (isTaskItem(item)) {
    if (activeTab.value === 'processed') {
      return [
        `${t('page.oaLite.processDetail.startUser')}：${item.processInstance?.startUser?.nickname || '-'}`,
        `${t('page.oaLite.item.approvalComment')}：${item.reason || '-'}`,
        `${t('page.oaLite.item.duration')}：${formatPast2(item.durationInMillis || 0)}`,
      ];
    }
    return [
      `${t('page.oaLite.processDetail.startUser')}：${item.processInstance?.startUser?.nickname || '-'}`,
      `${t('page.oaLite.processDetail.processNo')}：${item.processInstanceId}`,
      `${t('page.oaLite.item.taskNo')}：${item.id}`,
    ];
  }
  return [
    `${t('page.oaLite.filters.categoryPlaceholder')}：${item.categoryName || item.category || '-'}`,
    `${t('page.oaLite.processDetail.businessKey')}：${item.businessKey || '-'}`,
    `${t('page.oaLite.processDetail.processNo')}：${item.id}`,
  ];
}

function getKeywordPlaceholder() {
  switch (activeTab.value) {
    case 'copied': {
      return t('page.oaLite.filters.processNamePlaceholder');
    }
    case 'initiated': {
      return t('page.oaLite.filters.processNamePlaceholder');
    }
    case 'pending': {
      return t('page.oaLite.filters.taskNamePlaceholder');
    }
    case 'processed': {
      return t('page.oaLite.filters.taskNamePlaceholder');
    }
    default: {
      return t('page.oaLite.filters.keywordPlaceholder');
    }
  }
}

function getCreateTimePlaceholder(): [string, string] {
  return activeTab.value === 'copied'
    ? [t('page.oaLite.filters.copyStartTime'), t('page.oaLite.filters.copyEndTime')]
    : [t('page.oaLite.filters.startLaunchTime'), t('page.oaLite.filters.endLaunchTime')];
}

function getTabErrorMessage(tab: ListTab) {
  switch (tab) {
    case 'copied': {
      return t('page.oaLite.messages.loadCopiedFailed');
    }
    case 'initiated': {
      return t('page.oaLite.messages.loadInitiatedFailed');
    }
    case 'pending': {
      return t('page.oaLite.messages.loadPendingFailed');
    }
    case 'processed': {
      return t('page.oaLite.messages.loadProcessedFailed');
    }
  }
}

function applyLeaveDefinitionFilterDefaults() {
  listTabs.forEach((tab) => {
    if (tab === 'copied') {
      listFilters[tab].processDefinitionId = undefined;
      return;
    }
    listFilters[tab].processDefinitionKey = undefined;
  });
}

function getLeaveProcessVariables() {
  if (!leaveForm.startTime || !leaveForm.endTime) {
    return {};
  }
  const day = dayjs(Number(leaveForm.endTime)).diff(
    dayjs(Number(leaveForm.startTime)),
    'day',
  );
  return { day };
}

function isStartUserSelectableNode(node: BpmProcessInstanceApi.ApprovalNodeInfo) {
  return node.candidateStrategy === BpmCandidateStrategyEnum.START_USER_SELECT;
}

function syncTimelineCustomUsers() {
  if (!timelineRef.value?.batchSetCustomApproveUsers) {
    return;
  }
  const selectedUserMap = Object.entries(leaveForm.startUserSelectAssignees).reduce<
    Record<string, SystemUserApi.User[]>
  >((acc, [activityId, userIds]) => {
    if (!Array.isArray(userIds) || userIds.length === 0) {
      acc[activityId] = [];
      return acc;
    }
    const activityNode = activityNodes.value.find((node) => node.id === activityId);
    const activityCandidates = activityNode?.candidateUsers || [];
    acc[activityId] = userIds
      .map((userId) => {
        return (
          activityCandidates.find((candidate) => candidate.id === userId) ||
          selectableUsers.value.find((user) => user.id === userId)
        );
      })
      .filter(Boolean) as SystemUserApi.User[];
    return acc;
  }, {});
  timelineRef.value.batchSetCustomApproveUsers(selectedUserMap);
}

function handleStartUserSelectConfirm(activityId: string, userList: SystemUserApi.User[]) {
  leaveForm.startUserSelectAssignees[activityId] = (userList || []).map(
    (user) => Number(user.id),
  );
  syncTimelineCustomUsers();
}

async function loadLeaveDefinition() {
  const definitionList = await getProcessDefinitionList({
    suspensionState: 1,
  }).catch(() => []);
  const filteredDefinitions = (definitionList || []).filter((item) =>
    String(item.key || '').startsWith('oa_'),
  );
  oaTemplateDefinitions.value = filteredDefinitions;
  const definitions = OA_TEMPLATE_CONFIGS.map((item) => {
    const definition =
      filteredDefinitions.find((definitionItem) => definitionItem.key === item.processKey) ||
      null;
    return [item.key, definition] as const;
  });
  processDefinitions.value = Object.fromEntries(definitions);
  leaveProcessDefinition.value = processDefinitions.value.leave || null;
}

async function loadBaseOptions() {
  const [categoryList, userList] = await Promise.all([
    getCategorySimpleList(),
    getSimpleUserList(),
  ]);
  categories.value = categoryList;
  selectableUsers.value = userList;
}

async function loadLeaveApprovalPreview() {
  if (!currentTemplateDefinition.value?.id) {
    activityNodes.value = [];
    startUserSelectTasks.value = [];
    await nextTick();
    syncTimelineCustomUsers();
    return;
  }
  const data = await getApprovalDetail({
    processDefinitionId: currentTemplateDefinition.value.id,
    activityId: BpmNodeIdEnum.START_USER_NODE_ID,
    processVariablesStr: JSON.stringify(getLeaveProcessVariables()),
  });
  activityNodes.value = data?.activityNodes || [];
  startUserSelectTasks.value = activityNodes.value.filter((node) =>
    isStartUserSelectableNode(node),
  );
  const nextAssignees: Record<string, number[]> = {};
  startUserSelectTasks.value.forEach((node) => {
    nextAssignees[node.id] = leaveForm.startUserSelectAssignees[node.id] || [];
  });
  leaveForm.startUserSelectAssignees = nextAssignees;
  await nextTick();
  syncTimelineCustomUsers();
}

async function loadTabData(tab: ListTab) {
  tabLoading[tab] = true;
  try {
    const pageState = tabPages[tab];
    const filter = listFilters[tab];
    const createTime = filter.createTime ? [...filter.createTime] : undefined;

    switch (tab) {
      case 'initiated': {
        const resp = await getProcessInstanceMyPage({
          pageNo: pageState.pageNo,
          pageSize: pageState.pageSize,
          name: filter.name.trim() || undefined,
          category: filter.category,
          processDefinitionKey: filter.processDefinitionKey,
          status: filter.status,
          createTime,
        });
        initiatedItems.value = resp.list || [];
        pageState.total = resp.total || 0;
        break;
      }
      case 'pending': {
        const resp = await getTaskTodoPage({
          pageNo: pageState.pageNo,
          pageSize: pageState.pageSize,
          name: filter.name.trim() || undefined,
          category: filter.category,
          processDefinitionKey: filter.processDefinitionKey,
          createTime,
        });
        todoItems.value = resp.list || [];
        pageState.total = resp.total || 0;
        break;
      }
      case 'processed': {
        const resp = await getTaskDonePage({
          pageNo: pageState.pageNo,
          pageSize: pageState.pageSize,
          name: filter.name.trim() || undefined,
          category: filter.category,
          processDefinitionKey: filter.processDefinitionKey,
          status: filter.status,
          createTime,
        });
        doneItems.value = dedupeDoneTasks(resp.list || []);
        pageState.total = doneItems.value.length;
        break;
      }
      case 'copied': {
        const resp = await getProcessInstanceCopyPage({
          pageNo: pageState.pageNo,
          pageSize: pageState.pageSize,
          processInstanceName: filter.name.trim() || undefined,
          processDefinitionId: filter.processDefinitionId,
          createTime,
        });
        copiedItems.value = resp.list || [];
        pageState.total = resp.total || 0;
        break;
      }
    }
    tabInitialized[tab] = true;
    if (activeTab.value === tab) {
      syncSelectedItem(tab);
    }
  } catch (error: any) {
    message.error(error?.message || getTabErrorMessage(tab));
  } finally {
    tabLoading[tab] = false;
  }
}

async function refreshAllTabs() {
  loading.value = true;
  try {
    await Promise.all(listTabs.map((tab) => loadTabData(tab)));
  } finally {
    loading.value = false;
  }
}

function resetLeaveForm() {
  leaveForm.type = undefined;
  leaveForm.startTime = '';
  leaveForm.endTime = '';
  leaveForm.reason = '';
  leaveForm.startUserSelectAssignees = {};
}

function openComplexForm(
  templateKey: Extract<OaTemplateKey, 'document' | 'project' | 'seal' | 'staffing'>,
  businessKey?: string,
) {
  currentTemplateKey.value = templateKey;
  complexFormBusinessKey.value = businessKey;
  viewState.value = 'complex-form';
}

async function openLeaveForm(
  businessKey?: string,
  templateKey: OaTemplateKey = 'leave',
) {
  currentTemplateKey.value = templateKey;
  if (!currentTemplateDefinition.value) {
    await loadLeaveDefinition();
  }
  if (!currentTemplateDefinition.value) {
    message.error(t('page.oaLite.messages.leaveModelMissing'));
    return;
  }
  resetLeaveForm();
  leavePublishing.value = true;
  try {
    if (businessKey) {
      const businessId = Number(businessKey);
      if (!Number.isNaN(businessId) && businessId > 0) {
        const detail = await currentTemplateConfig.value.getDetailRequest(
          businessId,
        );
        leaveForm.type = detail.type;
        leaveForm.startTime = String(detail.startTime);
        leaveForm.endTime = String(detail.endTime);
        leaveForm.reason = detail.reason || '';
      }
    }
    await loadLeaveApprovalPreview();
    viewState.value = 'leave-form';
  } finally {
    leavePublishing.value = false;
  }
}

async function submitLeave() {
  if (!currentTemplateDefinition.value) {
    message.error(t('page.oaLite.messages.leaveModelCannotStart'));
    return;
  }
  if (
    leaveForm.type === undefined ||
    !leaveForm.startTime ||
    !leaveForm.endTime ||
    !leaveForm.reason.trim()
  ) {
    message.warning(t('page.oaLite.messages.fillLeaveForm'));
    return;
  }
  for (const node of startUserSelectTasks.value) {
    const assignees = leaveForm.startUserSelectAssignees[node.id] || [];
    if (
      isStartUserSelectableNode(node) &&
      assignees.length === 0
    ) {
      message.warning(t('ui.selectRequired', [`${node.name}${t('page.oaLite.item.approver')}`]));
      return;
    }
  }
  leaveSubmitting.value = true;
  try {
    await currentTemplateConfig.value.createRequest({
      endTime: Number(leaveForm.endTime),
      reason: leaveForm.reason.trim(),
      startTime: Number(leaveForm.startTime),
      startUserSelectAssignees: leaveForm.startUserSelectAssignees,
      type: leaveForm.type,
    });
    message.success(t('page.oaLite.messages.leaveStarted'));
    viewState.value = 'main';
    activeTab.value = 'initiated';
    tabPages.initiated.pageNo = 1;
    await refreshAllTabs();
    syncSelectedItem('initiated');
  } finally {
    leaveSubmitting.value = false;
  }
}

async function handleNotificationGetUnreadCount() {
  headerUnreadCount.value = await getUnreadNotifyMessageCount();
}

async function handleNotificationGetList() {
  const list = await getUnreadNotifyMessageList();
  headerNotifications.value = list.map((item) => ({
    avatar: preferences.app.defaultAvatar,
    date: formatDateTime(item.createTime) as string,
    id: item.id,
    isRead: false,
    message: item.templateContent,
    title: item.templateNickname,
  }));
}

function handleNotificationViewAll() {
  router.push({
    name: 'MyNotifyMessage',
  });
}

async function handleNotificationMakeAll() {
  realtimeNotifications.value = [];
  await updateAllNotifyMessageRead();
  headerUnreadCount.value = 0;
  headerNotifications.value = [];
}

async function handleNotificationClear() {
  await handleNotificationMakeAll();
}

async function handleNotificationRead(item: NotificationItem) {
  if (!item.id) {
    return;
  }
  if (isRealtimeNotificationItem(item)) {
    removeRealtimeNotification(item.id);
    return;
  }
  await updateNotifyMessageRead([item.id]);
  await handleNotificationGetUnreadCount();
  headerNotifications.value = headerNotifications.value.filter(
    (notificationItem) => notificationItem.id !== item.id,
  );
}

function handleNotificationOpen(open: boolean) {
  if (!open) {
    return;
  }
  handleNotificationGetList();
  handleNotificationGetUnreadCount();
}

function parseTaskAssignedWebSocketMessage(
  rawMessage: string,
): null | OaTaskAssignedWebSocketMessage {
  if (rawMessage === 'pong') {
    return null;
  }
  const envelope = JSON.parse(rawMessage);
  if (envelope.type !== OA_LITE_TASK_ASSIGNED_MESSAGE_TYPE || !envelope.content) {
    return null;
  }
  return JSON.parse(envelope.content) as OaTaskAssignedWebSocketMessage;
}

function isRealtimeNotificationItem(item: NotificationItem) {
  return String(item.id).startsWith(OA_LITE_TASK_ASSIGNED_NOTIFICATION_PREFIX);
}

function removeRealtimeNotification(id: NotificationItem['id']) {
  realtimeNotifications.value = realtimeNotifications.value.filter(
    (item) => item.id !== id,
  );
}

function upsertRealtimeTaskAssignedNotification(
  messagePayload: OaTaskAssignedWebSocketMessage,
) {
  const notificationId = `${OA_LITE_TASK_ASSIGNED_NOTIFICATION_PREFIX}${messagePayload.taskId}`;
  const notification: NotificationItem = {
    avatar: preferences.app.defaultAvatar,
    date: formatDateTime(Date.now()) as string,
    id: notificationId,
    isRead: false,
    message: `${messagePayload.startUserNickname} 提交了新的审批待办：${messagePayload.taskName}`,
    title: '审批待办',
  };
  realtimeNotifications.value = [
    notification,
    ...realtimeNotifications.value.filter((item) => item.id !== notificationId),
  ].slice(0, 10);
}

async function openPendingTaskDetail(taskId: string) {
  activeTab.value = 'pending';
  viewState.value = 'main';
  if (!tabInitialized.pending) {
    await loadTabData('pending');
  }
  const matchedTask = todoItems.value.find((item) => String(item.id) === String(taskId));
  if (matchedTask) {
    selectedItem.value = matchedTask;
    return;
  }
  await loadTabData('pending');
  selectedItem.value =
    todoItems.value.find((item) => String(item.id) === String(taskId)) || todoItems.value[0] || null;
}

async function handleTaskAssignedWebSocketMessage(
  messagePayload: OaTaskAssignedWebSocketMessage,
) {
  upsertRealtimeTaskAssignedNotification(messagePayload);
  await Promise.all([
    handleNotificationGetUnreadCount(),
    loadTabData('pending'),
  ]);
  if (activeTab.value === 'pending') {
    syncSelectedItem('pending');
  }
  message.open({
    content: `${messagePayload.startUserNickname} 提交了新的审批待办：${messagePayload.taskName}`,
    duration: 4,
    key: OA_LITE_TASK_ASSIGNED_TOAST_KEY,
    onClick: () => {
      openPendingTaskDetail(messagePayload.taskId);
    },
    type: 'info',
  });
}

async function handleLogout() {
  await authStore.logout(false);
}

function openProfileCenter() {
  viewState.value = 'profile';
}

function openTemplateCreate(
  templateKey: OaTemplateKey,
  businessKey?: string,
) {
  const targetConfig =
    OA_TEMPLATE_CONFIGS.find((item) => item.key === templateKey) ||
    OA_TEMPLATE_CONFIGS[0];
  if (
    targetConfig.key === 'document' ||
    targetConfig.key === 'project' ||
    targetConfig.key === 'seal' ||
    targetConfig.key === 'staffing'
  ) {
    openComplexForm(targetConfig.key, businessKey);
    return;
  }
  openLeaveForm(businessKey, templateKey);
}

function handleProcessRecreate(
  businessKey: string,
  processDefinitionKey?: string,
  formCustomCreatePath?: string,
) {
  const targetConfig = OA_TEMPLATE_CONFIGS.find(
    (item) => item.processKey === processDefinitionKey,
  );
  if (
    targetConfig?.key === 'document' ||
    targetConfig?.key === 'project' ||
    targetConfig?.key === 'seal' ||
    targetConfig?.key === 'staffing'
  ) {
    openComplexForm(targetConfig.key, businessKey);
    return;
  }
  if (formCustomCreatePath) {
    router.push({
      path: formCustomCreatePath,
      query: { id: businessKey },
    });
    return;
  }
  openLeaveForm(businessKey, (targetConfig?.key as OaTemplateKey) || 'leave');
}

function selectCreateCategory(code: string) {
  selectedCreateCategoryCode.value = code;
  const target = createCategorySectionElements.value[code];
  if (!target || typeof window === 'undefined') {
    return;
  }
  const top = target.getBoundingClientRect().top + window.scrollY - 132;
  window.scrollTo({
    behavior: 'smooth',
    top: Math.max(top, 0),
  });
}

function setCreateCategorySectionRef(code: string, element: HTMLElement | null) {
  if (!element) {
    delete createCategorySectionElements.value[code];
    return;
  }
  createCategorySectionElements.value[code] = element;
}

function syncCreateCategoryByScroll() {
  if (
    typeof window === 'undefined' ||
    activeTab.value !== 'create' ||
    viewState.value !== 'main'
  ) {
    return;
  }
  const sections = createCategorySections.value
    .map((item) => ({
      code: item.code,
      element: createCategorySectionElements.value[item.code],
    }))
    .filter(
      (
        item,
      ): item is {
        code: string;
        element: HTMLElement;
      } => Boolean(item.element),
    );
  if (sections.length === 0) {
    return;
  }
  const threshold = 156;
  let matchedCode = sections[0]?.code;
  sections.forEach((section) => {
    const top = section.element.getBoundingClientRect().top;
    if (top <= threshold) {
      matchedCode = section.code;
    }
  });
  selectedCreateCategoryCode.value = matchedCode;
}

function openTab(tab: MainTab) {
  activeTab.value = tab;
  viewState.value = 'main';
}

async function handleFilterSubmit() {
  if (activeTab.value === 'create') {
    return;
  }
  tabPages[activeTab.value].pageNo = 1;
  await loadTabData(activeTab.value);
}

async function resetCurrentFilter() {
  if (activeTab.value === 'create') {
    return;
  }
  Object.assign(listFilters[activeTab.value], createDefaultFilter());
  tabPages[activeTab.value].pageNo = 1;
  await loadTabData(activeTab.value);
}

async function handlePageChange(page: number, pageSize: number) {
  if (activeTab.value === 'create') {
    return;
  }
  const pageState = tabPages[activeTab.value];
  pageState.pageNo = page;
  pageState.pageSize = pageSize;
  await loadTabData(activeTab.value);
}

async function handleDetailRefresh() {
  await refreshAllTabs();
  if (activeTab.value !== 'create') {
    syncSelectedItem(activeTab.value);
  }
}

function openMainNav(section: 'center' | 'create') {
  if (section === 'create') {
    openTab('create');
    return;
  }
  openTab(activeTab.value === 'create' ? lastCenterTab.value : activeTab.value);
}

watch(
  createCategoryTabs,
  (tabs) => {
    if (tabs.length === 0) {
      selectedCreateCategoryCode.value = undefined;
      return;
    }
    if (
      selectedCreateCategoryCode.value &&
      tabs.some((item) => item.code === selectedCreateCategoryCode.value)
    ) {
      return;
    }
    selectedCreateCategoryCode.value = tabs[0].code;
    nextTick(() => {
      syncCreateCategoryByScroll();
    });
  },
  {
    immediate: true,
  },
);

watch(
  [activeTab, viewState, createCategorySections],
  () => {
    nextTick(() => {
      syncCreateCategoryByScroll();
    });
  },
  { deep: true },
);

watch(
  () => [currentTemplateKey.value, leaveForm.type, leaveForm.startTime, leaveForm.endTime],
  async () => {
    if (viewState.value !== 'leave-form' || !currentTemplateDefinition.value) {
      return;
    }
    await loadLeaveApprovalPreview();
  },
);

watch(
  () => activeTab.value,
  async (tab) => {
    if (tab !== 'create') {
      lastCenterTab.value = tab;
    }
    if (tab === 'create') {
      selectedItem.value = null;
      return;
    }
    if (!tabInitialized[tab]) {
      await loadTabData(tab);
      return;
    }
    syncSelectedItem(tab);
  },
);

watch(
  () => webSocketData.value,
  async (rawMessage) => {
    if (!rawMessage) {
      return;
    }
    try {
      const messagePayload = parseTaskAssignedWebSocketMessage(rawMessage);
      if (!messagePayload) {
        return;
      }
      await handleTaskAssignedWebSocketMessage(messagePayload);
    } catch (error) {
      console.error('处理 OA 实时待办消息失败', error);
    }
  },
);

onMounted(async () => {
  if (typeof document !== 'undefined') {
    document.body.classList.add(OA_LITE_BODY_THEME_CLASS);
  }
  try {
    await Promise.all([
      loadBaseOptions(),
      loadLeaveDefinition(),
      syncCurrentUserProfile(),
    ]);
    await handleNotificationGetUnreadCount();
    notificationPollingTimer = setInterval(() => {
      if (userStore.userInfo) {
        handleNotificationGetUnreadCount();
      }
    }, 1000 * 60 * 2);
    if (availableTemplateDefinitions.value.length === 0) {
      message.error(t('page.oaLite.messages.leaveModelMissing'));
      return;
    }
    applyLeaveDefinitionFilterDefaults();
    await refreshAllTabs();
  } catch (error: any) {
    message.error(error?.message || t('page.oaLite.messages.loadPageFailed'));
  }
  if (typeof window !== 'undefined') {
    window.addEventListener('scroll', syncCreateCategoryByScroll, { passive: true });
  }
});

onUnmounted(() => {
  if (typeof document !== 'undefined') {
    document.body.classList.remove(OA_LITE_BODY_THEME_CLASS);
  }
  if (notificationPollingTimer) {
    clearInterval(notificationPollingTimer);
    notificationPollingTimer = null;
  }
  if (typeof window !== 'undefined') {
    window.removeEventListener('scroll', syncCreateCategoryByScroll);
  }
  closeWebSocket();
});
</script>

<template>
  <ConfigProvider :theme="oaLiteTheme">
    <div class="oa-lite-page">
      <div class="oa-lite-bg"></div>

      <template v-if="viewState === 'leave-form' || viewState === 'complex-form'">
        <div class="oa-lite-leave-page">
          <header class="oa-lite-leave-header">
            <div class="oa-lite-leave-left">
              <button class="oa-lite-leave-back" @click="viewState = 'main'">
                <IconifyIcon icon="lucide:chevron-left" />
              </button>
              <div class="oa-lite-leave-header-tabs">
                <div class="oa-lite-leave-header-tab active">{{ t('page.oaLite.topbar.create') }}</div>
              </div>
            </div>
          </header>

          <template v-if="viewState === 'leave-form'">
            <main class="oa-lite-leave-main">
              <div class="oa-lite-leave-shell">
                <div class="oa-lite-leave-card">
                  <div class="oa-lite-leave-title-row">
                    <div>
                      <h1 class="oa-lite-leave-title">{{ currentTemplateConfig.title }}</h1>
                      <p class="oa-lite-leave-subtitle">{{ currentTemplateConfig.subtitle }}</p>
                    </div>
                    <IconifyIcon :icon="currentTemplateConfig.icon" class="oa-lite-leave-qr" />
                  </div>

                  <div class="oa-lite-leave-divider"></div>

                  <Form layout="vertical">
                    <Form.Item :label="currentTemplateConfig.typeLabel" required>
                      <Select
                        v-model:value="leaveForm.type"
                        :options="currentTemplateTypeOptions"
                        :placeholder="currentTemplateConfig.typePlaceholder"
                        popup-class-name="oa-lite-select-popup"
                        :get-popup-container="(triggerNode) => triggerNode.parentNode"
                      />
                    </Form.Item>
                    <Form.Item :label="currentTemplateConfig.startTimeLabel" required>
                      <DatePicker
                        v-model:value="leaveForm.startTime"
                        show-time
                        value-format="x"
                        format="YYYY-MM-DD HH:mm:ss"
                        class="w-full"
                        :placeholder="currentTemplateConfig.startTimePlaceholder"
                      />
                    </Form.Item>
                    <Form.Item :label="currentTemplateConfig.endTimeLabel" required>
                      <DatePicker
                        v-model:value="leaveForm.endTime"
                        show-time
                        value-format="x"
                        format="YYYY-MM-DD HH:mm:ss"
                        class="w-full"
                        :placeholder="currentTemplateConfig.endTimePlaceholder"
                      />
                    </Form.Item>
                    <Form.Item :label="currentTemplateConfig.reasonLabel" required>
                      <Input.TextArea
                        v-model:value="leaveForm.reason"
                        :rows="4"
                        :placeholder="currentTemplateConfig.reasonPlaceholder"
                      />
                    </Form.Item>
                  </Form>
                </div>

                <div class="oa-lite-leave-card">
                  <div class="oa-lite-leave-flow-head">
                    <div class="oa-lite-leave-flow-title">{{ t('page.oaLite.leaveForm.flowTitle') }}</div>
                    <div class="oa-lite-leave-flow-tag">{{ t('page.oaLite.leaveForm.flowTag') }}</div>
                  </div>

                  <div class="oa-lite-leave-flow-body">
                    <ProcessInstanceTimeline
                      ref="timelineRef"
                      :activity-nodes="activityNodes"
                      :show-status-icon="false"
                      @select-user-confirm="handleStartUserSelectConfirm"
                    />
                  </div>

                  <div class="oa-lite-leave-submit-row">
                    <Button type="primary" :loading="leaveSubmitting" @click="submitLeave">
                      {{ currentTemplateConfig.submitLabel }}
                    </Button>
                  </div>
                </div>
              </div>
            </main>
          </template>

          <OaLiteComplexTemplateForm
            v-else
            :key="`${currentTemplateKey}-${complexFormBusinessKey || 'create'}`"
            :business-key="complexFormBusinessKey"
            :template-key="currentTemplateKey as 'document' | 'project' | 'seal' | 'staffing'"
            @back="viewState = 'main'"
            @success="
              viewState = 'main';
              activeTab = 'initiated';
              tabPages.initiated.pageNo = 1;
              refreshAllTabs();
            "
          />
        </div>
      </template>

      <template v-else>
        <header class="oa-lite-topbar">
          <div class="oa-lite-topbar-inner">
            <div class="oa-lite-brand">
              <div class="oa-lite-brand-icon">
                <IconifyIcon icon="lucide:file-heart" />
              </div>
              <div>
                <div class="oa-lite-brand-title">{{ t('page.oaLite.brand.title') }}</div>
                <div class="oa-lite-brand-subtitle">{{ t('page.oaLite.brand.subtitle') }}</div>
              </div>
            </div>

            <nav class="oa-lite-topnav">
              <button
                class="oa-lite-topnav-tab"
                :class="{ active: topNavKey === 'create' }"
                @click="openMainNav('create')"
              >
                {{ t('page.oaLite.topbar.create') }}
              </button>
              <button
                class="oa-lite-topnav-tab"
                :class="{ active: topNavKey === 'center' }"
                @click="openMainNav('center')"
              >
                {{ t('page.oaLite.topbar.center') }}
              </button>
            </nav>

            <div class="oa-lite-user-actions">
              <Button class="oa-lite-white-button oa-lite-refresh-button" @click="handleDetailRefresh">
                <IconifyIcon icon="lucide:refresh-cw" />
                {{ t('page.oaLite.topbar.refresh') }}
              </Button>
              <div class="oa-lite-header-widget-bar">
                <ThemeToggle class="oa-lite-header-widget" />
                <LanguageToggle class="oa-lite-header-widget" />
                <VbenFullScreen class="oa-lite-header-widget" />
                <TimezoneButton class="oa-lite-header-widget" />
                <Notification
                  class="oa-lite-header-widget"
                  :dot="showNotificationDot"
                  :notifications="mergedNotifications"
                  @clear="handleNotificationClear"
                  @make-all="handleNotificationMakeAll"
                  @open="handleNotificationOpen"
                  @read="handleNotificationRead"
                  @view-all="handleNotificationViewAll"
                />
                <UserDropdown
                  :avatar="avatar"
                  :description="userStore.userInfo?.email"
                  :menus="headerMenus"
                  :tag-text="userStore.userInfo?.username"
                  :text="userStore.userInfo?.nickname"
                  class="oa-lite-header-user"
                  @logout="handleLogout"
                />
              </div>
            </div>
          </div>
        </header>

        <main class="oa-lite-main">
          <div class="oa-lite-home-shell">
            <template v-if="viewState === 'profile'">
              <section class="oa-lite-profile-shell">
                <div class="oa-lite-profile-header">
                  <div>
                    <div class="oa-lite-section-title">{{ t('page.oaLite.profileCenter.title') }}</div>
                    <div class="oa-lite-section-desc">
                      {{ t('page.oaLite.profileCenter.subtitle') }}
                    </div>
                  </div>
                </div>
                <div class="oa-lite-profile-content">
                  <ProfileCenter />
                </div>
              </section>
            </template>

            <template v-else-if="activeTab === 'create'">
              <section class="oa-lite-stat-pillar">
                <button
                  v-for="item in dashboardNavItems"
                  :key="item.key"
                  class="oa-lite-stat-item"
                  @click="openTab(item.key)"
                >
                  <span class="oa-lite-stat-count">{{ item.count }}</span>
                  <IconifyIcon :icon="item.icon" class="oa-lite-stat-icon" />
                  <span class="oa-lite-stat-label">{{ item.label }}</span>
                  <IconifyIcon icon="lucide:chevron-right" class="oa-lite-stat-arrow" />
                </button>
              </section>

	              <section class="oa-lite-create-shell">
	                <div class="oa-lite-create-toolbar">
	                  <div v-if="createCategoryTabs.length > 0" class="oa-lite-category-tabs">
	                    <button
                      v-for="item in createCategoryTabs"
                      :key="item.code"
                      class="oa-lite-category-tab"
                      :class="{ active: currentCreateCategoryCode === item.code }"
                      @click="selectCreateCategory(item.code)"
                    >
	                      {{ item.name }}
	                    </button>
	                  </div>
	                </div>

	                <div class="oa-lite-create-sections">
	                  <section
	                    v-for="section in createCategorySections"
	                    :key="section.code"
	                    :ref="(element) => setCreateCategorySectionRef(section.code, element as HTMLElement | null)"
	                    class="oa-lite-template-section"
	                  >
	                    <div class="oa-lite-template-section-head">
	                      <span class="oa-lite-template-section-title">
	                        {{ section.name }}
	                      </span>
	                      <IconifyIcon icon="lucide:hash" class="oa-lite-template-section-arrow" />
	                    </div>

	                    <div v-if="section.templates.length > 0" class="oa-lite-template-grid">
	                      <button
	                        v-for="item in section.templates"
	                        :key="item.key"
	                        class="oa-lite-template-card"
	                        @click="openTemplateCreate(item.key)"
	                      >
	                        <div class="oa-lite-template-icon">
	                          <IconifyIcon :icon="item.icon" />
	                        </div>
	                        <div class="oa-lite-template-body">
	                          <div class="oa-lite-template-name">{{ item.title }}</div>
	                          <div class="oa-lite-template-desc">
	                            {{ item.description }}
	                          </div>
	                        </div>
	                      </button>
	                    </div>
	                    <Empty
	                      v-else
	                      :description="t('page.oaLite.createCard.emptyCategory')"
	                      :image-style="{ height: '80px' }"
	                    />
	                  </section>
	                </div>
	              </section>
	            </template>

            <template v-else>
              <section class="oa-lite-center-shell">
                <aside class="oa-lite-center-nav">
                  <button
                    v-for="item in dashboardNavItems"
                    :key="item.key"
                    class="oa-lite-center-nav-item"
                    :class="{ active: activeTab === item.key }"
                    @click="openTab(item.key)"
                  >
                    <span class="oa-lite-center-nav-main">
                      <span class="oa-lite-center-nav-icon">
                        <IconifyIcon :icon="item.icon" />
                      </span>
                      <span class="oa-lite-center-nav-text">{{ item.label }}</span>
                    </span>
                    <Tag class="oa-lite-center-nav-count">{{ item.count }}</Tag>
                  </button>
                </aside>

                <div class="oa-lite-center-content">
                  <div class="oa-lite-list-panel">
                    <div class="oa-lite-section-header oa-lite-list-header">
                      <div>
                        <div class="oa-lite-section-title">{{ currentListTitle }}</div>
                        <div class="oa-lite-section-desc">{{ currentListSubtitle }}</div>
                      </div>
                      <Button type="link" @click="resetCurrentFilter">{{ t('page.oaLite.filters.resetFilters') }}</Button>
                    </div>

                    <div class="oa-lite-filters">
                      <Input
                        v-model:value="currentFilter!.name"
                        :placeholder="getKeywordPlaceholder()"
                        allow-clear
                        @press-enter="handleFilterSubmit"
                      >
                        <template #prefix>
                          <IconifyIcon icon="lucide:search" />
                        </template>
                      </Input>

                      <Select
                        v-if="showProcessFilter"
                        v-model:value="currentProcessFilterValue"
                        class="oa-lite-filter-control"
                        :placeholder="t('page.oaLite.filters.processPlaceholder')"
                        allow-clear
                        :options="currentProcessOptions"
                        popup-class-name="oa-lite-status-popup"
                        :get-popup-container="(triggerNode) => triggerNode.parentNode"
                      />

                      <Select
                        v-if="showCategoryFilter"
                        v-model:value="currentFilter!.category"
                        class="oa-lite-filter-control"
                        :placeholder="t('page.oaLite.filters.categoryPlaceholder')"
                        allow-clear
                        :options="categoryOptions"
                        popup-class-name="oa-lite-status-popup"
                        :get-popup-container="(triggerNode) => triggerNode.parentNode"
                      />

                      <Select
                        v-if="showStatusFilter"
                        v-model:value="currentFilter!.status"
                        class="oa-lite-filter-control"
                        :placeholder="activeTab === 'processed' ? t('page.oaLite.filters.approvalStatusPlaceholder') : t('page.oaLite.filters.processStatusPlaceholder')"
                        allow-clear
                        :options="currentStatusOptions"
                        popup-class-name="oa-lite-status-popup"
                        :get-popup-container="(triggerNode) => triggerNode.parentNode"
                      />

                      <DatePicker.RangePicker
                        v-model:value="currentFilter!.createTime"
                        class="oa-lite-filter-range"
                        show-time
                        value-format="YYYY-MM-DD HH:mm:ss"
                        format="YYYY-MM-DD HH:mm:ss"
                        :placeholder="getCreateTimePlaceholder()"
                      />
                    </div>

                    <div class="oa-lite-filter-actions">
                      <Button type="primary" @click="handleFilterSubmit">{{ t('page.oaLite.filters.search') }}</Button>
                      <Button class="oa-lite-white-button" @click="resetCurrentFilter">
                        {{ t('page.oaLite.filters.reset') }}
                      </Button>
                    </div>

                    <Spin :spinning="currentListLoading">
                      <div v-if="currentList.length > 0" class="oa-lite-list">
                        <button
                          v-for="item in currentList"
                          :key="getItemIdentity(item)"
                          class="oa-lite-list-item"
                          :class="{ active: selectedItem === item }"
                          @click="selectedItem = item"
                        >
                          <div class="oa-lite-list-head">
                            <div class="oa-lite-list-title">{{ getItemTitle(item) }}</div>
                            <span class="oa-lite-list-date">{{ getItemMetaRight(item) }}</span>
                          </div>
                          <div class="oa-lite-list-summary">{{ getItemSummary(item) }}</div>
                          <div class="oa-lite-list-meta">
                            <span>{{ getItemMetaLeft(item) }}</span>
                            <Tag
                              v-if="getItemStatus(item) !== undefined"
                              class="oa-lite-list-status-tag"
                              :class="`tone-${getItemStatusTone(item)}`"
                            >
                              {{ getItemStatusText(item) }}
                            </Tag>
                          </div>
                          <div class="oa-lite-list-extra">
                            <span
                              v-for="row in getExtraMetaRows(item)"
                              :key="`${getItemTitle(item)}-${row}`"
                            >
                              {{ row }}
                            </span>
                          </div>
                        </button>
                      </div>
                      <Empty v-else :description="t('page.oaLite.empty.noData', [currentListTitle])" />
                    </Spin>

                    <div
                      v-if="currentPageState && currentPageState.total > 0"
                      class="oa-lite-pagination-wrap"
                    >
                      <Pagination
                        :current="currentPageState.pageNo"
                        :page-size="currentPageState.pageSize"
                        :total="currentPageState.total"
                        :show-size-changer="true"
                        :show-total="(total) => t('page.oaLite.pagination.total', [total])"
                        @change="handlePageChange"
                      />
                    </div>
                  </div>

                  <div class="oa-lite-detail-panel">
                    <ProcessDetail
                      v-if="currentDetailRequest"
                      :request="currentDetailRequest"
                      :section="currentDetailSection"
                      @refresh="handleDetailRefresh"
                      @recreate="handleProcessRecreate"
                    />
                    <div v-else class="oa-lite-detail-empty">
                      <Empty :description="t('page.oaLite.empty.selectDetail', [currentListTitle])" />
                    </div>
                  </div>
                </div>
              </section>
            </template>
          </div>
        </main>
      </template>
    </div>
  </ConfigProvider>
</template>

<style lang="scss" scoped>
.oa-lite-page {
  min-height: 100vh;
  background: #f7f8fa;
  color: #111827;
  position: relative;
}

.oa-lite-page :deep(.bg-card),
.oa-lite-page :deep(.bg-background),
.oa-lite-page :deep(.bg-popover) {
  background: #fff !important;
}

.oa-lite-page :deep(.bg-background-deep) {
  background: #f7f8fa !important;
}

.oa-lite-page :deep(.bg-accent),
.oa-lite-page :deep(.bg-muted),
.oa-lite-page :deep(.bg-secondary),
.oa-lite-page :deep(.bg-gray-100),
.oa-lite-page :deep(.dark\:bg-gray-600) {
  background: #f8fafc !important;
}

.oa-lite-page :deep(.border-border) {
  border-color: #dbe5f0 !important;
}

.oa-lite-page :deep(.text-foreground),
.oa-lite-page :deep(.text-card-foreground),
.oa-lite-page :deep(.text-popover-foreground),
.oa-lite-page :deep(.text-accent-foreground) {
  color: #111827 !important;
}

.oa-lite-page :deep(.text-muted-foreground),
.oa-lite-page :deep(.text-gray-500),
.oa-lite-page :deep([class~='text-foreground/80']),
.oa-lite-page :deep([class~='text-foreground/60']) {
  color: #64748b !important;
}

.oa-lite-page :deep(.ant-empty-description),
.oa-lite-page :deep(.ant-spin-text),
.oa-lite-page :deep(.ant-pagination-total-text),
.oa-lite-page :deep(.ant-pagination .ant-pagination-item a),
.oa-lite-page :deep(.ant-select-selection-item),
.oa-lite-page :deep(.ant-select-selection-search-input),
.oa-lite-page :deep(.ant-picker-input > input),
.oa-lite-page :deep(.ant-form-item-label > label),
.oa-lite-page :deep(.ant-alert-message),
.oa-lite-page :deep(.ant-alert-description),
.oa-lite-page :deep(.ant-input-prefix),
.oa-lite-page :deep(.ant-input-show-count-suffix),
.oa-lite-page :deep(.ant-picker-suffix),
.oa-lite-page :deep(.ant-picker-clear),
.oa-lite-page :deep(.ant-select-arrow),
.oa-lite-page :deep(.ant-select-clear) {
  color: #111827 !important;
}

.oa-lite-page :deep(.ant-form-item-extra),
.oa-lite-page :deep(.ant-form-item-explain),
.oa-lite-page :deep(.ant-pagination-options),
.oa-lite-page :deep(.ant-empty-normal) {
  color: #64748b !important;
}

.oa-lite-page :deep(.ant-btn:not(.ant-btn-primary):not(.ant-btn-dangerous)),
.oa-lite-page :deep(.ant-btn:not(.ant-btn-primary):not(.ant-btn-dangerous) > span),
.oa-lite-page :deep(.ant-btn-link),
.oa-lite-page :deep(.ant-btn-link > span) {
  color: #111827 !important;
}

.oa-lite-bg {
  position: fixed;
  inset: 0 auto auto 0;
  width: 100%;
  height: 420px;
  background:
    radial-gradient(circle at 20% 10%, rgb(221 234 255 / 90%), transparent 38%),
    linear-gradient(180deg, rgb(238 244 255 / 85%) 0%, rgb(247 248 250 / 0%) 100%);
  pointer-events: none;
  z-index: 0;
  opacity: 0.6;
}

.oa-lite-topbar,
.oa-lite-main,
.oa-lite-leave-page {
  position: relative;
  z-index: 1;
}

.oa-lite-topbar {
  padding: 20px 24px 0;
}

.oa-lite-topbar-inner {
  max-width: 1260px;
  margin: 0 auto;
  display: grid;
  grid-template-columns: auto minmax(0, 1fr) auto;
  align-items: center;
  gap: 24px;
}

.oa-lite-brand {
  display: flex;
  align-items: center;
  gap: 14px;
}

.oa-lite-brand-icon {
  width: 42px;
  height: 42px;
  border-radius: 14px;
  background: linear-gradient(135deg, #ff9a3d 0%, #ff6a00 100%);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 20px;
  box-shadow: 0 8px 20px rgb(255 106 0 / 28%);
}

.oa-lite-brand-title {
  font-size: 20px;
  font-weight: 700;
}

.oa-lite-brand-subtitle {
  margin-top: 4px;
  color: #64748b;
  font-size: 13px;
}

.oa-lite-topnav {
  display: flex;
  align-items: center;
  justify-content: center;
  gap: 34px;
}

.oa-lite-topnav-tab {
  position: relative;
  border: none;
  background: transparent;
  padding: 8px 2px 10px;
  color: #6b7280;
  font-size: 15px;
  font-weight: 600;
  cursor: pointer;
  transition: color 0.18s ease;
}

.oa-lite-topnav-tab:hover,
.oa-lite-topnav-tab.active {
  color: #111827;
}

.oa-lite-topnav-tab.active::after {
  content: '';
  position: absolute;
  left: 50%;
  bottom: 0;
  width: 20px;
  height: 3px;
  transform: translateX(-50%);
  border-radius: 999px;
  background: #111827;
}

.oa-lite-user-actions {
  display: flex;
  align-items: center;
  gap: 12px;
  justify-content: flex-end;
  flex-wrap: wrap;
}

.oa-lite-refresh-button {
  white-space: nowrap;
}

.oa-lite-header-widget-bar {
  display: flex;
  align-items: center;
  padding: 4px 8px 4px 10px;
  border: 1px solid #e7edf4;
  border-radius: 999px;
  background: rgb(255 255 255 / 92%);
  box-shadow: 0 10px 24px rgb(15 23 42 / 6%);
  backdrop-filter: blur(14px);
}

.oa-lite-header-widget-bar :deep(.text-foreground),
.oa-lite-header-widget-bar :deep(.text-muted-foreground),
.oa-lite-header-widget-bar :deep(.anticon),
.oa-lite-header-widget-bar :deep(svg) {
  color: #111827 !important;
}

.oa-lite-header-widget-bar :deep(.mr-1),
.oa-lite-header-widget-bar :deep(.mr-2) {
  margin-right: 4px !important;
}

.oa-lite-header-widget-bar :deep(.ml-1) {
  margin-left: 0 !important;
}

.oa-lite-header-widget-bar :deep(.hover\:bg-accent:hover),
.oa-lite-header-widget-bar :deep(.hover\:text-accent-foreground:hover) {
  color: #111827 !important;
}

.oa-lite-header-user :deep(.mr-2) {
  margin-right: 0 !important;
}

.oa-lite-main {
  padding: 18px 24px 32px;
}

.oa-lite-home-shell {
  max-width: 1260px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 22px;
}

.oa-lite-stat-pillar {
  align-self: center;
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  justify-content: center;
  overflow: hidden;
  border: 1px solid #eef2f7;
  border-radius: 999px;
  background: rgb(255 255 255 / 94%);
  box-shadow: 0 10px 30px rgb(15 23 42 / 6%);
  backdrop-filter: blur(14px);
}

.oa-lite-stat-item {
  border: none;
  background: transparent;
  padding: 12px 20px;
  display: inline-flex;
  align-items: center;
  gap: 8px;
  color: #475569;
  cursor: pointer;
  transition:
    background-color 0.18s ease,
    color 0.18s ease;
}

.oa-lite-stat-item + .oa-lite-stat-item {
  border-left: 1px solid #edf2f7;
}

.oa-lite-stat-item:hover {
  background: #f8fbff;
  color: #2563eb;
}

.oa-lite-stat-count {
  min-width: 28px;
  height: 28px;
  padding: 0 8px;
  border-radius: 999px;
  background: #f3f4f6;
  color: #111827;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 13px;
  font-weight: 700;
}

.oa-lite-stat-item:hover .oa-lite-stat-count {
  background: #eff6ff;
  color: #2563eb;
}

.oa-lite-stat-icon,
.oa-lite-stat-arrow {
  color: #94a3b8;
  font-size: 15px;
}

.oa-lite-stat-label {
  font-size: 14px;
  font-weight: 500;
}

.oa-lite-create-shell {
  width: 100%;
  max-width: 1000px;
  margin: 0 auto;
}

.oa-lite-create-sections {
  display: flex;
  flex-direction: column;
  gap: 28px;
}

.oa-lite-profile-shell {
  width: 100%;
  max-width: 1260px;
}

.oa-lite-profile-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 18px;
}

.oa-lite-profile-content {
  border: 1px solid #e7edf4;
  border-radius: 24px;
  background: rgb(255 255 255 / 92%);
  box-shadow: 0 12px 34px rgb(15 23 42 / 5%);
  padding: 22px;
}

.oa-lite-profile-content :deep(.ant-card) {
  border-color: #e7edf4 !important;
  border-radius: 20px !important;
  box-shadow: none !important;
}

.oa-lite-profile-content :deep(.ant-card-head) {
  border-bottom-color: #edf2f7 !important;
}

.oa-lite-profile-content :deep(.ant-tabs-nav::before) {
  border-bottom-color: #edf2f7 !important;
}

.oa-lite-create-toolbar {
  position: sticky;
  top: 0;
  z-index: 3;
  display: flex;
  align-items: center;
  justify-content: flex-start;
  gap: 16px;
  padding: 8px 0 20px;
  background: rgb(247 248 250 / 88%);
  backdrop-filter: blur(14px);
}

.oa-lite-category-tabs {
  display: flex;
  align-items: center;
  gap: 30px;
  overflow-x: auto;
  scrollbar-width: none;
}

.oa-lite-category-tabs::-webkit-scrollbar {
  display: none;
}

.oa-lite-category-tab {
  position: relative;
  border: none;
  background: transparent;
  padding: 0 0 12px;
  color: #6b7280;
  font-size: 15px;
  font-weight: 600;
  white-space: nowrap;
  cursor: pointer;
  transition: color 0.18s ease;
}

.oa-lite-category-tab:hover,
.oa-lite-category-tab.active {
  color: #111827;
}

.oa-lite-category-tab.active::after {
  content: '';
  position: absolute;
  left: 50%;
  bottom: 0;
  transform: translateX(-50%);
  width: 18px;
  height: 3px;
  border-radius: 999px;
  background: #111827;
}

.oa-lite-template-section {
  scroll-margin-top: 128px;
}

.oa-lite-template-section-head {
  display: flex;
  align-items: center;
  justify-content: space-between;
  margin-bottom: 16px;
  padding-bottom: 10px;
  border-bottom: 1px solid #edf2f7;
}

.oa-lite-template-section-title {
  font-size: 18px;
  color: #111827;
  font-weight: 600;
}

.oa-lite-template-section-arrow {
  color: #cbd5e1;
  font-size: 14px;
}

.oa-lite-template-grid {
  display: grid;
  grid-template-columns: repeat(4, minmax(0, 1fr));
  gap: 16px;
}

.oa-lite-template-card {
  min-height: 82px;
  border: 1px solid transparent;
  background: #fff;
  border-radius: 20px;
  padding: 18px;
  display: flex;
  align-items: center;
  gap: 14px;
  text-align: left;
  cursor: pointer;
  box-shadow: 0 1px 8px rgb(0 0 0 / 4%);
  transition:
    transform 0.18s ease,
    border-color 0.18s ease,
    box-shadow 0.18s ease;
}

.oa-lite-template-card:hover {
  transform: translateY(-1px);
  border-color: #dbeafe;
  box-shadow: 0 10px 24px rgb(59 130 246 / 10%);
}

.oa-lite-template-card:disabled {
  cursor: wait;
  opacity: 0.82;
}

.oa-lite-template-icon {
  width: 44px;
  height: 44px;
  border-radius: 14px;
  background: linear-gradient(135deg, #60a5fa 0%, #2563eb 100%);
  color: #fff;
  display: flex;
  align-items: center;
  justify-content: center;
  font-size: 18px;
  flex-shrink: 0;
}

.oa-lite-template-body {
  min-width: 0;
}

.oa-lite-template-name {
  font-size: 15px;
  font-weight: 600;
  color: #191919;
}

.oa-lite-template-desc {
  margin-top: 4px;
  font-size: 12px;
  color: #94a3b8;
  line-height: 1.5;
}

.oa-lite-center-shell {
  display: grid;
  grid-template-columns: 180px minmax(0, 1fr);
  gap: 18px;
  align-items: start;
}

.oa-lite-center-nav {
  padding: 12px 0;
}

.oa-lite-center-nav-item {
  width: calc(100% - 8px);
  margin: 0 4px 8px;
  border: none;
  border-radius: 16px;
  background: transparent;
  padding: 12px 14px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 10px;
  color: #64748b;
  cursor: pointer;
  transition:
    background-color 0.18s ease,
    box-shadow 0.18s ease,
    color 0.18s ease;
}

.oa-lite-center-nav-item:hover {
  background: rgb(15 23 42 / 4%);
  color: #111827;
}

.oa-lite-center-nav-item.active {
  background: #fff;
  color: #111827;
  box-shadow: 0 4px 14px rgb(15 23 42 / 6%);
}

.oa-lite-center-nav-main {
  display: inline-flex;
  align-items: center;
  gap: 10px;
  min-width: 0;
}

.oa-lite-center-nav-icon {
  font-size: 16px;
  color: inherit;
  display: inline-flex;
  align-items: center;
}

.oa-lite-center-nav-text {
  font-size: 14px;
  font-weight: 500;
  white-space: nowrap;
}

.oa-lite-center-nav-count.ant-tag {
  min-width: 28px;
  height: 24px;
  padding: 0 8px;
  margin-inline-end: 0;
  border-radius: 999px;
  border: 1px solid #e5e7eb;
  background: #fff !important;
  color: #334155 !important;
  display: inline-flex;
  align-items: center;
  justify-content: center;
}

.oa-lite-center-content {
  display: grid;
  grid-template-columns: 340px minmax(0, 1fr);
  gap: 18px;
}

.oa-lite-list-panel,
.oa-lite-detail-panel {
  background: #fff;
  border: 1px solid #e7edf4;
  border-radius: 22px;
  box-shadow: 0 1px 10px rgb(0 0 0 / 4%);
  min-width: 0;
}

.oa-lite-list-panel {
  padding: 18px;
}

.oa-lite-detail-panel {
  padding: 18px;
  min-height: 680px;
}

.oa-lite-section-header {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  margin-bottom: 18px;
}

.oa-lite-list-header {
  margin-bottom: 16px;
}

.oa-lite-section-title {
  font-size: 20px;
  font-weight: 700;
  color: #111827;
}

.oa-lite-section-desc {
  margin-top: 6px;
  color: #64748b;
  font-size: 13px;
  line-height: 1.6;
}

.oa-lite-filters {
  display: grid;
  grid-template-columns: 1fr;
  gap: 10px;
  margin-bottom: 14px;
}

.oa-lite-filter-control,
.oa-lite-filter-range {
  width: 100%;
}

.oa-lite-filter-actions {
  display: flex;
  justify-content: flex-end;
  gap: 12px;
  margin-bottom: 18px;
}

.oa-lite-list {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.oa-lite-list-item {
  width: 100%;
  border: 1px solid #edf2f7;
  background: #fff;
  border-radius: 16px;
  text-align: left;
  padding: 14px;
  cursor: pointer;
  transition:
    transform 0.18s ease,
    border-color 0.18s ease,
    box-shadow 0.18s ease,
    background-color 0.18s ease;
}

.oa-lite-list-item:hover {
  transform: translateY(-1px);
  border-color: #dbe5f0;
}

.oa-lite-list-item.active {
  border-color: #bfdbfe;
  box-shadow: 0 10px 24px rgb(37 99 235 / 8%);
  background: #f8fbff;
}

.oa-lite-list-head {
  display: flex;
  align-items: flex-start;
  justify-content: space-between;
  gap: 12px;
}

.oa-lite-list-title {
  font-size: 15px;
  font-weight: 600;
  color: #111827;
}

.oa-lite-list-date {
  font-size: 12px;
  color: #94a3b8;
  white-space: nowrap;
}

.oa-lite-list-summary {
  margin-top: 10px;
  font-size: 13px;
  line-height: 1.65;
  color: #475569;
}

.oa-lite-list-meta {
  margin-top: 12px;
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  color: #334155;
  font-size: 13px;
}

.oa-lite-list-status-tag.ant-tag {
  margin-inline-end: 0;
  border-radius: 999px;
  border: 1px solid #dbe5f0;
  background: #fff !important;
  color: #111827 !important;
}

.oa-lite-list-status-tag.ant-tag.tone-success {
  background: #ecfdf3 !important;
  border-color: #b7ebc6 !important;
  color: #027a48 !important;
}

.oa-lite-list-status-tag.ant-tag.tone-warning {
  background: #fffbeb !important;
  border-color: #fcd34d !important;
  color: #b45309 !important;
}

.oa-lite-list-status-tag.ant-tag.tone-danger {
  background: #fef2f2 !important;
  border-color: #fecaca !important;
  color: #b42318 !important;
}

.oa-lite-list-status-tag.ant-tag.tone-muted {
  background: #f8fafc !important;
  border-color: #cbd5e1 !important;
  color: #475569 !important;
}

.oa-lite-list-status-tag.ant-tag.tone-neutral {
  background: #eff6ff !important;
  border-color: #bfdbfe !important;
  color: #1d4ed8 !important;
}

.oa-lite-list-extra {
  margin-top: 10px;
  display: flex;
  flex-direction: column;
  gap: 4px;
  color: #64748b;
  font-size: 12px;
}

.oa-lite-pagination-wrap {
  margin-top: 18px;
  display: flex;
  justify-content: flex-end;
}

.oa-lite-detail-empty {
  min-height: 580px;
  display: flex;
  align-items: center;
  justify-content: center;
}

.oa-lite-white-button {
  height: 36px;
  padding: 0 16px;
  border-radius: 999px;
  background: #fff;
  border: 1px solid #dbe5f0;
  color: #111827;
  box-shadow: none;
}

.oa-lite-leave-page {
  min-height: 100vh;
  background: #f4f5f7;
  display: flex;
  flex-direction: column;
}

.oa-lite-leave-header {
  height: 56px;
  background: #fff;
  border-bottom: 1px solid #e5e7eb;
  display: flex;
  align-items: center;
  padding: 0 16px;
  position: sticky;
  top: 0;
  z-index: 20;
}

.oa-lite-leave-left {
  display: flex;
  align-items: center;
  gap: 24px;
}

.oa-lite-leave-back {
  width: 32px;
  height: 32px;
  border: none;
  border-radius: 10px;
  background: transparent;
  color: #4b5563;
  cursor: pointer;
}

.oa-lite-leave-header-tabs {
  display: flex;
  align-items: center;
  gap: 24px;
  height: 100%;
}

.oa-lite-leave-header-tab {
  height: 56px;
  display: flex;
  align-items: center;
  font-size: 15px;
  color: #111827;
  font-weight: 600;
  position: relative;
}

.oa-lite-leave-header-tab.active::after {
  content: '';
  position: absolute;
  left: 50%;
  bottom: 0;
  transform: translateX(-50%);
  width: 24px;
  height: 3px;
  border-radius: 999px;
  background: #111827;
}

.oa-lite-leave-main {
  flex: 1;
  overflow-y: auto;
  padding: 24px 0 80px;
}

.oa-lite-leave-shell {
  max-width: 800px;
  margin: 0 auto;
  display: flex;
  flex-direction: column;
  gap: 16px;
}

.oa-lite-leave-card {
  background: #fff;
  border-radius: 16px;
  border: 1px solid #eef1f4;
  box-shadow: 0 1px 8px rgb(0 0 0 / 4%);
  padding: 32px;
}

.oa-lite-leave-title-row {
  position: relative;
}

.oa-lite-leave-title {
  margin: 0;
  font-size: 30px;
  font-weight: 700;
  color: #111827;
}

.oa-lite-leave-subtitle {
  margin: 6px 0 0;
  font-size: 13px;
  color: #9ca3af;
}

.oa-lite-leave-qr {
  position: absolute;
  top: 0;
  right: 0;
  font-size: 32px;
  color: #d1d5db;
}

.oa-lite-leave-divider {
  border-bottom: 1px dashed #e5e7eb;
  padding-top: 14px;
  margin-bottom: 12px;
}

.oa-lite-leave-card :deep(.ant-form-item-label > label) {
  color: #374151;
  font-size: 13px;
}

.oa-lite-leave-card :deep(.ant-input),
.oa-lite-leave-card :deep(.ant-input-affix-wrapper),
.oa-lite-leave-card :deep(.ant-picker),
.oa-lite-leave-card :deep(.ant-select-selector),
.oa-lite-leave-card :deep(textarea.ant-input),
.oa-lite-list-panel :deep(.ant-input),
.oa-lite-list-panel :deep(.ant-input-affix-wrapper),
.oa-lite-list-panel :deep(.ant-picker),
.oa-lite-list-panel :deep(.ant-select-selector),
.oa-lite-list-panel :deep(textarea.ant-input),
.oa-lite-detail-panel :deep(.ant-input),
.oa-lite-detail-panel :deep(.ant-input-affix-wrapper),
.oa-lite-detail-panel :deep(.ant-picker),
.oa-lite-detail-panel :deep(.ant-select-selector),
.oa-lite-detail-panel :deep(textarea.ant-input) {
  background: #fff !important;
  color: #111827 !important;
  border: 1px solid #d1d5db !important;
  box-shadow: none !important;
}

.oa-lite-leave-card :deep(.ant-input::placeholder),
.oa-lite-leave-card :deep(textarea.ant-input::placeholder),
.oa-lite-leave-card :deep(.ant-select-selection-placeholder),
.oa-lite-leave-card :deep(.ant-picker-input input::placeholder),
.oa-lite-list-panel :deep(.ant-input::placeholder),
.oa-lite-list-panel :deep(textarea.ant-input::placeholder),
.oa-lite-list-panel :deep(.ant-select-selection-placeholder),
.oa-lite-list-panel :deep(.ant-picker-input input::placeholder),
.oa-lite-detail-panel :deep(.ant-input::placeholder),
.oa-lite-detail-panel :deep(textarea.ant-input::placeholder),
.oa-lite-detail-panel :deep(.ant-select-selection-placeholder),
.oa-lite-detail-panel :deep(.ant-picker-input input::placeholder) {
  color: #9ca3af !important;
}

.oa-lite-leave-card :deep(.ant-picker-input > input),
.oa-lite-leave-card :deep(.ant-select-selection-item),
.oa-lite-leave-card :deep(.ant-select-arrow),
.oa-lite-leave-card :deep(.ant-picker-suffix),
.oa-lite-leave-card :deep(.ant-picker-clear),
.oa-lite-list-panel :deep(.ant-picker-input > input),
.oa-lite-list-panel :deep(.ant-select-selection-item),
.oa-lite-list-panel :deep(.ant-select-arrow),
.oa-lite-list-panel :deep(.ant-picker-suffix),
.oa-lite-list-panel :deep(.ant-picker-clear),
.oa-lite-detail-panel :deep(.ant-picker-input > input),
.oa-lite-detail-panel :deep(.ant-select-selection-item),
.oa-lite-detail-panel :deep(.ant-select-arrow),
.oa-lite-detail-panel :deep(.ant-picker-suffix),
.oa-lite-detail-panel :deep(.ant-picker-clear) {
  color: #111827 !important;
}

.oa-lite-leave-card :deep(.ant-input:focus),
.oa-lite-leave-card :deep(.ant-input-affix-wrapper-focused),
.oa-lite-leave-card :deep(.ant-picker-focused),
.oa-lite-leave-card :deep(.ant-select-focused .ant-select-selector),
.oa-lite-leave-card :deep(textarea.ant-input:focus),
.oa-lite-list-panel :deep(.ant-input:focus),
.oa-lite-list-panel :deep(.ant-input-affix-wrapper-focused),
.oa-lite-list-panel :deep(.ant-picker-focused),
.oa-lite-list-panel :deep(.ant-select-focused .ant-select-selector),
.oa-lite-list-panel :deep(textarea.ant-input:focus),
.oa-lite-detail-panel :deep(.ant-input:focus),
.oa-lite-detail-panel :deep(.ant-input-affix-wrapper-focused),
.oa-lite-detail-panel :deep(.ant-picker-focused),
.oa-lite-detail-panel :deep(.ant-select-focused .ant-select-selector),
.oa-lite-detail-panel :deep(textarea.ant-input:focus) {
  border-color: #3b82f6 !important;
  box-shadow: 0 0 0 1px rgb(59 130 246 / 18%) !important;
}

:deep(.oa-lite-select-popup.ant-select-dropdown),
:deep(.oa-lite-status-popup.ant-select-dropdown) {
  background: #fff !important;
  border: 1px solid #d1d5db !important;
  box-shadow: 0 8px 24px rgb(15 23 42 / 10%) !important;
  border-radius: 16px !important;
  padding: 8px 0 !important;
}

:deep(.oa-lite-select-popup .ant-select-item),
:deep(.oa-lite-status-popup .ant-select-item) {
  color: #111827 !important;
  background: #fff !important;
}

:deep(.oa-lite-select-popup .ant-select-item-option-active:not(.ant-select-item-option-disabled)),
:deep(.oa-lite-status-popup .ant-select-item-option-active:not(.ant-select-item-option-disabled)) {
  background: #f3f4f6 !important;
}

:deep(.oa-lite-select-popup .ant-select-item-option-selected:not(.ant-select-item-option-disabled)),
:deep(.oa-lite-status-popup .ant-select-item-option-selected:not(.ant-select-item-option-disabled)) {
  background: #eff6ff !important;
  color: #2563eb !important;
}

.oa-lite-leave-flow-head {
  display: flex;
  align-items: center;
  border-bottom: 1px solid #f1f5f9;
  padding-bottom: 16px;
}

.oa-lite-leave-flow-title {
  font-size: 15px;
  font-weight: 700;
  color: #111827;
}

.oa-lite-leave-flow-tag {
  margin-left: 12px;
  font-size: 12px;
  color: #2563eb;
}

.oa-lite-leave-flow-body {
  position: relative;
  padding-top: 18px;
  padding-left: 18px;

  :deep(.ant-timeline) {
    margin: 0;
    padding-top: 0 !important;
  }

  :deep(.ant-timeline-item-content) {
    color: #111827;
  }

  :deep(.font-bold) {
    color: #111827;
    font-weight: 700;
  }

  :deep(.text-sm) {
    color: #334155;
  }

  :deep(.text-gray-500) {
    color: #64748b !important;
  }

  :deep(.bg-gray-100) {
    background: #f8fafc !important;
    color: #111827 !important;
  }

  :deep(.dark\:bg-gray-600) {
    background: #f8fafc !important;
  }

  :deep(.ant-btn.ant-btn-icon-only.ant-btn-background-ghost.ant-btn-primary) {
    width: auto;
    min-width: 116px;
    height: 36px;
    padding: 0 14px;
    border-radius: 12px;
    border-color: #dbe5f0;
    background: #fff;
    color: #111827;
    box-shadow: none;
  }

  :deep(.ant-btn.ant-btn-icon-only.ant-btn-background-ghost.ant-btn-primary::after) {
    content: v-bind(selectApproverLabel);
    margin-left: 6px;
    font-size: 13px;
    font-weight: 600;
    color: #111827;
  }

  :deep(.ant-btn.ant-btn-icon-only.ant-btn-background-ghost.ant-btn-primary:hover) {
    border-color: #bfdbfe;
    color: #2563eb;
  }

  :deep(.ant-btn.ant-btn-icon-only.ant-btn-background-ghost.ant-btn-primary:hover::after) {
    color: #2563eb;
  }
}

.oa-lite-leave-flow-line {
  position: absolute;
  top: 26px;
  bottom: 34px;
  left: 21px;
  width: 1px;
  background: #d1d5db;
}

.oa-lite-leave-flow-node {
  position: relative;
  display: flex;
  align-items: flex-start;
  gap: 22px;
  margin-bottom: 30px;
}

.oa-lite-leave-flow-node-last {
  margin-bottom: 0;
}

.oa-lite-leave-flow-dot {
  width: 12px;
  height: 12px;
  border-radius: 999px;
  background: #d1d5db;
  box-shadow: 0 0 0 4px #fff;
  position: relative;
  left: -3px;
  z-index: 2;
  flex-shrink: 0;
  margin-top: 4px;
}

.oa-lite-leave-node-title {
  font-size: 13px;
  font-weight: 600;
  color: #1f2937;
}

.oa-lite-leave-node-subtitle {
  margin-top: 2px;
  font-size: 11px;
  color: #9ca3af;
}

.oa-lite-leave-node-body {
  min-width: 0;
}

.oa-lite-leave-node-select {
  width: 220px;
  margin-top: 12px;
}

.oa-lite-leave-submit-row {
  padding-top: 20px;
}

@media (max-width: 1000px) {
  .oa-lite-topbar-inner {
    grid-template-columns: auto minmax(0, 1fr);
  }

  .oa-lite-user-actions {
    grid-column: 1 / -1;
    justify-content: flex-start;
  }

  .oa-lite-template-grid {
    grid-template-columns: repeat(3, minmax(0, 1fr));
  }
}

@media (max-width: 1024px) {
  .oa-lite-topbar-inner {
    grid-template-columns: 1fr;
    justify-items: start;
  }

  .oa-lite-topnav {
    justify-content: flex-start;
  }

  .oa-lite-center-shell,
  .oa-lite-center-content {
    grid-template-columns: 1fr;
  }

  .oa-lite-center-nav {
    display: grid;
    grid-template-columns: repeat(2, minmax(0, 1fr));
    gap: 8px;
    padding: 0;
  }

  .oa-lite-center-nav-item {
    width: 100%;
    margin: 0;
  }

  .oa-lite-template-grid {
    grid-template-columns: repeat(2, minmax(0, 1fr));
  }
}

@media (max-width: 768px) {
  .oa-lite-topbar {
    padding: 16px 14px 0;
  }

  .oa-lite-main {
    padding: 14px 14px 20px;
  }

  .oa-lite-stat-pillar {
    width: 100%;
    flex-wrap: nowrap;
    justify-content: flex-start;
    overflow-x: auto;
  }

  .oa-lite-stat-item {
    flex: 0 0 auto;
  }

  .oa-lite-center-nav {
    grid-template-columns: 1fr;
  }

  .oa-lite-create-search {
    display: none;
  }

  .oa-lite-list-panel,
  .oa-lite-detail-panel {
    padding: 16px;
    border-radius: 18px;
  }

  .oa-lite-template-grid {
    grid-template-columns: 1fr;
  }

  .oa-lite-section-header {
    flex-direction: column;
    align-items: flex-start;
  }

  .oa-lite-leave-shell {
    padding: 0 14px;
  }

  .oa-lite-leave-card {
    padding: 20px;
  }
}
</style>

<style lang="scss">
body.oa-lite-light-theme {
  --background: 0 0% 100%;
  --background-deep: 216 20.11% 95.47%;
  --foreground: 210 6% 21%;
  --muted: 240 4.8% 95.9%;
  --muted-foreground: 240 3.8% 46.1%;
  --accent: 240 5% 96%;
  --accent-hover: 200deg 10% 90%;
  --accent-foreground: 240 6% 10%;
  --border: 240 5.9% 90%;
}

body.oa-lite-light-theme .z-popup,
body.oa-lite-light-theme [role='dialog'],
body.oa-lite-light-theme [role='menu'] {
  background: #fff !important;
  border-color: #dbe5f0 !important;
  color: #111827 !important;
  box-shadow: 0 18px 40px rgb(15 23 42 / 12%) !important;
}

body.oa-lite-light-theme .z-popup .bg-popover,
body.oa-lite-light-theme .z-popup .bg-background,
body.oa-lite-light-theme .z-popup .bg-card,
body.oa-lite-light-theme .z-popup .text-popover-foreground,
body.oa-lite-light-theme .z-popup .text-foreground,
body.oa-lite-light-theme .z-popup .text-card-foreground,
body.oa-lite-light-theme .z-popup .text-muted-foreground,
body.oa-lite-light-theme [role='dialog'] .bg-popover,
body.oa-lite-light-theme [role='dialog'] .bg-background,
body.oa-lite-light-theme [role='dialog'] .bg-card,
body.oa-lite-light-theme [role='menu'] .bg-popover,
body.oa-lite-light-theme [role='menu'] .bg-background,
body.oa-lite-light-theme [role='menu'] .bg-card {
  background: #fff !important;
  color: #111827 !important;
}

body.oa-lite-light-theme .z-popup .text-muted-foreground,
body.oa-lite-light-theme [role='dialog'] .text-muted-foreground,
body.oa-lite-light-theme [role='menu'] .text-muted-foreground {
  color: #64748b !important;
}

body.oa-lite-light-theme .z-popup .border-border,
body.oa-lite-light-theme [role='dialog'] .border-border,
body.oa-lite-light-theme [role='menu'] .border-border {
  border-color: #e5e7eb !important;
}

body.oa-lite-light-theme .z-popup [data-highlighted],
body.oa-lite-light-theme .z-popup .hover\:bg-accent:hover,
body.oa-lite-light-theme [role='menu'] [data-highlighted],
body.oa-lite-light-theme [role='menu'] .hover\:bg-accent:hover,
body.oa-lite-light-theme [role='dialog'] .hover\:bg-accent:hover {
  background: #f3f4f6 !important;
  color: #111827 !important;
}

body.oa-lite-light-theme .z-popup button,
body.oa-lite-light-theme .z-popup svg,
body.oa-lite-light-theme .z-popup .anticon,
body.oa-lite-light-theme [role='dialog'] button,
body.oa-lite-light-theme [role='dialog'] svg,
body.oa-lite-light-theme [role='menu'] button,
body.oa-lite-light-theme [role='menu'] svg {
  color: #111827 !important;
}
</style>
