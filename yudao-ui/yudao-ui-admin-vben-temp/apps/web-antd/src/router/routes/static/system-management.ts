import type { RouteRecordRaw } from 'vue-router';

const BasicLayout = () => import('#/layouts/basic.vue');

const routes: RouteRecordRaw[] = [
  {
    path: '/system',
    component: BasicLayout,
    meta: {
      hideInMenu: true,
      title: '系统管理',
    },
    children: [
      {
        path: 'meeting-room',
        name: 'SystemMeetingRoomStatic',
        component: () => import('#/views/system/meeting-room/index.vue'),
        meta: {
          title: '会议室管理',
          activePath: '/system/meeting-room',
          hideInMenu: true,
          keepAlive: true,
        },
      },
      {
        path: 'meeting-booking',
        name: 'SystemMeetingBookingStatic',
        component: () => import('#/views/system/meeting-booking/index.vue'),
        meta: {
          title: '会议室预定',
          activePath: '/system/meeting-booking',
          hideInMenu: true,
          keepAlive: true,
        },
      },
      {
        path: 'meeting-booking/schedule',
        name: 'SystemMeetingBookingScheduleStatic',
        component: () => import('#/views/system/meeting-booking/schedule.vue'),
        meta: {
          title: '会议室排期',
          activePath: '/system/meeting-booking/schedule',
          hideInMenu: true,
          keepAlive: true,
        },
      },
      {
        path: 'personal-schedule',
        name: 'SystemPersonalScheduleStatic',
        component: () => import('#/views/system/personal-schedule/index.vue'),
        meta: {
          title: '个人日程',
          activePath: '/system/personal-schedule',
          hideInMenu: true,
          keepAlive: true,
        },
      },
      {
        path: 'notice',
        name: 'SystemNoticeStatic',
        component: () => import('#/views/system/notice/index.vue'),
        meta: {
          title: '通知公告',
          activePath: '/system/notice',
          hideInMenu: true,
          keepAlive: true,
        },
      },
    ],
  },
];

export default routes;
